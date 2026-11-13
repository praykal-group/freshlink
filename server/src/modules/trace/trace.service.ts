import { HttpStatus, Injectable } from '@nestjs/common';
import type { Prisma } from '@prisma/client';
import { AppError } from '../../common/errors/app-error';
import { GENESIS_HASH, traceHash, traceSignature, verifyChain, verifyTraceSignature } from '../../common/hashing/hashing';
import { AppConfig } from '../../config/config.service';
import { PrismaService } from '../../infra/prisma/prisma.service';

export const TRACE_EVENT_TYPES = [
  'REGISTERED', 'TAGGED', 'IMAGED', 'GRADED', 'GRADE_DISPUTED', 'GRADE_RESOLVED', 'STORED', 'BATCH_CORRECTED',
  'ALLOCATED', 'LOADED', 'DEPARTED', 'EXCURSION', 'SHELF_LIFE_UPDATED', 'DIVERTED', 'RESCUED', 'RECEIVED',
  'DELIVERED', 'REJECTED',
] as const;
export type TraceEventType = (typeof TRACE_EVENT_TYPES)[number];

type Tx = Prisma.TransactionClient;

/** Hash-chained, insert-only journey log per batch (W-4, SYN-14). */
@Injectable()
export class TraceService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly config: AppConfig,
  ) {}

  /**
   * Appends one event. MUST run inside the caller's transaction so the event commits with the
   * change it describes. The batch row lock serialises concurrent appends for the same batch.
   */
  async append(
    tx: Tx,
    batchId: string,
    eventType: TraceEventType,
    payload: Record<string, unknown>,
    actorUserId: string | null,
    occurredAt: Date = new Date(),
  ) {
    const locked = await tx.$queryRaw<{ id: string }[]>`SELECT id FROM batches WHERE id = ${batchId}::uuid FOR UPDATE`;
    if (!locked.length) throw new AppError('NOT_FOUND', 'Batch not found', HttpStatus.NOT_FOUND);

    const last = await tx.traceEvent.findFirst({ where: { batchId }, orderBy: { seq: 'desc' }, select: { seq: true, hash: true } });
    const seq = (last?.seq ?? 0) + 1;
    const prevHash = last?.hash ?? GENESIS_HASH;
    // Millisecond precision on both sides: Postgres timestamptz keeps µs, JS Date keeps ms.
    const at = new Date(Math.floor(occurredAt.getTime()));
    const hash = traceHash(prevHash, eventType, payload, at);
    return tx.traceEvent.create({
      data: { batchId, seq, eventType, payload: payload as Prisma.InputJsonValue, actorUserId, occurredAt: at, prevHash, hash },
    });
  }

  events(batchId: string) {
    return this.prisma.traceEvent.findMany({ where: { batchId }, orderBy: { seq: 'asc' } });
  }

  async verify(batchId: string) {
    const events = await this.events(batchId);
    return verifyChain(events);
  }

  private get key(): string {
    const key = this.config.get('TRACE_SIGNING_KEY');
    if (!key) throw new AppError('TRACE_NOT_CONFIGURED', 'TRACE_SIGNING_KEY is not set', HttpStatus.SERVICE_UNAVAILABLE);
    return key;
  }

  /** Public signed URL printed on the label QR (SYN-09). */
  traceUrl(code: string): string {
    const base = this.config.get('APP_BASE_URL').replace(/\/+$/, '');
    return `${base}/t/${encodeURIComponent(code)}?s=${traceSignature(code, this.key)}`;
  }

  isValidSignature(code: string, sig: unknown): boolean {
    return verifyTraceSignature(code, sig, this.key);
  }
}
