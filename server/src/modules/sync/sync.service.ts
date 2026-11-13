import { Injectable, Logger } from '@nestjs/common';
import { Prisma, type UserRole } from '@prisma/client';
import { plainToInstance, type ClassConstructor } from 'class-transformer';
import { validate } from 'class-validator';
import type { AuthUser } from '../../common/auth/auth-user';
import { AppError } from '../../common/errors/app-error';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { BatchesService } from '../batches/batches.service';
import { AttachImageDto, AttachTagDto, CreateBatchDto, EditableBatchFieldsDto, ReceiveDto } from '../batches/dto/batch.dto';
import type { SyncOpDto, SyncResult, SyncType } from './sync.dto';

type Handler = (user: AuthUser, payload: Record<string, unknown>, op: SyncOpDto, deviceId?: string) => Promise<unknown>;

class InvalidPayload extends AppError {}

/**
 * Same role rules as the REST routes. Controller @Roles do not apply here because /sync calls
 * the services directly, so each op type is checked explicitly.
 */
const OP_ROLES: Partial<Record<SyncType, UserRole[]>> = {
  BATCH_CREATE: ['OPERATOR', 'ADMIN'],
  BATCH_UPDATE: ['OPERATOR', 'ADMIN'],
  TAG_ATTACH: ['OPERATOR', 'ADMIN'],
  IMAGE_ATTACH: ['OPERATOR', 'ADMIN'],
  RECEIVE: ['OPERATOR', 'ADMIN'],
};

/** Ops are applied oldest first (capturedAt); a stable sort keeps client order for equal times. */
export function orderOps<T extends { capturedAt: string }>(ops: T[]): T[] {
  return ops
    .map((op, i) => ({ op, i, t: Date.parse(op.capturedAt) }))
    .sort((a, b) => a.t - b.t || a.i - b.i)
    .map((x) => x.op);
}

/** Splits `{batchId, ...rest}` payloads. */
function batchIdOf(payload: Record<string, unknown>): { batchId: string; rest: Record<string, unknown> } {
  const { batchId, ...rest } = payload;
  if (typeof batchId !== 'string' || !/^[0-9a-f-]{36}$/i.test(batchId)) {
    throw new InvalidPayload('VALIDATION_FAILED', 'payload.batchId must be a UUID', 400);
  }
  return { batchId, rest };
}

async function parse<T extends object>(cls: ClassConstructor<T>, plain: Record<string, unknown>): Promise<T> {
  const dto = plainToInstance(cls, plain);
  const errors = await validate(dto, { whitelist: true, forbidNonWhitelisted: true });
  if (errors.length) {
    const messages = errors.flatMap((e) => [
      ...Object.values(e.constraints ?? {}),
      ...(e.children ?? []).flatMap((c) => Object.values(c.constraints ?? {})),
    ]);
    throw new InvalidPayload('VALIDATION_FAILED', 'Invalid op payload', 400, { errors: messages });
  }
  return dto;
}

/**
 * POST /sync (Section 6.4): the offline outbox. Idempotent per clientOpId through sync_ops.
 * Client errors (4xx) are stored so a retry gets the same answer; server errors (5xx) are not
 * stored, so the phone retries them later. Types of later milestones answer UNSUPPORTED (not stored).
 */
@Injectable()
export class SyncService {
  private readonly logger = new Logger(SyncService.name);
  private readonly handlers: Partial<Record<SyncType, Handler>>;

  constructor(
    private readonly prisma: PrismaService,
    batches: BatchesService,
  ) {
    this.handlers = {
      BATCH_CREATE: async (user, p, _op, deviceId) => batches.create(user, await parse(CreateBatchDto, p), deviceId),
      BATCH_UPDATE: async (user, p, op) => {
        const { batchId, rest } = batchIdOf(p);
        return batches.update(user, batchId, await parse(EditableBatchFieldsDto, rest), new Date(op.capturedAt));
      },
      TAG_ATTACH: async (user, p) => {
        const { batchId, rest } = batchIdOf(p);
        return batches.attachTag(user, batchId, await parse(AttachTagDto, rest));
      },
      IMAGE_ATTACH: async (user, p) => {
        const { batchId, rest } = batchIdOf(p);
        return batches.attachImage(user, batchId, await parse(AttachImageDto, rest));
      },
      RECEIVE: async (user, p) => {
        const { batchId, rest } = batchIdOf(p);
        return batches.receive(user, batchId, await parse(ReceiveDto, rest));
      },
    };
  }

  async process(user: AuthUser, ops: SyncOpDto[], deviceId?: string): Promise<{ results: SyncResult[] }> {
    const results: SyncResult[] = [];
    for (const op of orderOps(ops)) results.push(await this.one(user, op, deviceId));
    return { results };
  }

  private async one(user: AuthUser, op: SyncOpDto, deviceId?: string): Promise<SyncResult> {
    const stored = await this.prisma.syncOp.findUnique({ where: { clientOpId: op.clientOpId } });
    if (stored) {
      if (stored.userId !== user.id) {
        return { clientOpId: op.clientOpId, type: op.type, status: 'REJECTED', error: { code: 'DUPLICATE', message: 'clientOpId already used' } };
      }
      return { ...(stored.result as unknown as SyncResult), replayed: true };
    }

    const handler = this.handlers[op.type];
    if (!handler) {
      return {
        clientOpId: op.clientOpId,
        type: op.type,
        status: 'UNSUPPORTED',
        error: { code: 'NOT_YET_SUPPORTED', message: `${op.type} is processed from a later release; keep it queued` },
      };
    }

    let result: SyncResult;
    try {
      const allowed = OP_ROLES[op.type];
      if (allowed && !allowed.includes(user.role)) {
        throw new AppError('FORBIDDEN_ROLE', `${user.role} cannot send ${op.type}`, 403);
      }
      result ={ clientOpId: op.clientOpId, type: op.type, status: 'APPLIED', data: await handler(user, op.payload, op, deviceId) };
    } catch (e) {
      const status = e instanceof AppError ? e.getStatus() : 500;
      const error = e instanceof AppError
        ? { code: e.code, message: e.message, details: e.details }
        : { code: 'INTERNAL_ERROR', message: 'Temporary server error; retry later' };
      if (status >= 500 || status === 408 || status === 429) {
        if (!(e instanceof AppError)) this.logger.error(e);
        return { clientOpId: op.clientOpId, type: op.type, status: 'ERROR', error };
      }
      result = { clientOpId: op.clientOpId, type: op.type, status: 'REJECTED', error };
    }

    try {
      await this.prisma.syncOp.create({
        data: { clientOpId: op.clientOpId, userId: user.id, type: op.type, result: result as unknown as Prisma.InputJsonValue },
      });
    } catch (e) {
      // The same op arrived twice concurrently: answer with whatever the first one stored.
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') {
        const first = await this.prisma.syncOp.findUnique({ where: { clientOpId: op.clientOpId } });
        if (first) return { ...(first.result as unknown as SyncResult), replayed: true };
      }
      throw e;
    }
    return result;
  }
}
