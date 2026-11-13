import { HttpStatus, Injectable, Logger } from '@nestjs/common';
import type { Grade, Prisma, QualityGrade } from '@prisma/client';
import type { AuthUser } from '../../common/auth/auth-user';
import { Ownership } from '../../common/auth/ownership';
import { AppError } from '../../common/errors/app-error';
import { afterCursor, type PageQuery, toPage } from '../../common/pagination';
import { EventBus } from '../../infra/events/event-bus.service';
import { MlCallError, MlClient } from '../../infra/ml/ml-client.service';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { BatchesService } from '../batches/batches.service';
import { FilesService } from '../files/files.service';
import { ShelfLifeService } from '../shelf-life/shelf-life.service';
import { TraceService } from '../trace/trace.service';
import { pickGradingImages } from './grading-rules';

interface MlGrade {
  batchId: string;
  grade: Grade;
  confidence: number;
  defects: { class: string; conf: number; box: number[]; areaPct: number }[];
  perImage: unknown[];
  modelVersion: string;
  latencyMs: number;
}

/** SYN-05 target: grade within 3 s of the request (server side). Image download is inside this budget. */
const ML_TIMEOUT_MS = 8000;

function fail(code: string, message: string, status: HttpStatus, details?: Record<string, unknown>): never {
  throw new AppError(code, message, status, details);
}

const view = (g: QualityGrade) => ({ ...g, confidence: Number(g.confidence) });

@Injectable()
export class GradingService {
  private readonly logger = new Logger(GradingService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly batches: BatchesService,
    private readonly files: FilesService,
    private readonly ml: MlClient,
    private readonly trace: TraceService,
    private readonly shelfLife: ShelfLifeService,
    private readonly events: EventBus,
  ) {}

  /** POST /batches/:id/grade: synchronous ML call (FO-FR-07). The app queues and retries on 503. */
  async grade(user: AuthUser, batchId: string) {
    const started = Date.now();
    const batch = await this.batches.loadForUser(user, batchId);
    Ownership.assertSite(user, batch.currentSiteId);
    if (['DELIVERED', 'REJECTED', 'SPOILED'].includes(batch.status)) {
      fail('INVALID_STATUS', `Cannot grade a batch with status ${batch.status}`, HttpStatus.CONFLICT);
    }
    const [product, images] = await Promise.all([
      this.prisma.product.findUniqueOrThrow({ where: { id: batch.productId }, select: { category: true } }),
      this.prisma.batchImage.findMany({ where: { batchId }, select: { view: true, s3Key: true, capturedAt: true } }),
    ]);
    const pick = pickGradingImages(images);
    if (!pick.ok) {
      fail('IMAGES_REQUIRED', `Take the ${pick.missing.join(', ').toLowerCase()} photo first`, HttpStatus.CONFLICT, { missing: pick.missing });
    }
    const imageUrls = await Promise.all(pick.keys.map((k) => this.files.internalUrl(k)));

    let result: MlGrade;
    try {
      result = await this.ml.post<MlGrade>('/v1/vision/grade', { batchId, category: product.category, imageUrls }, ML_TIMEOUT_MS);
    } catch (e) {
      const err = e as MlCallError;
      if (err.status === 503 || err.status === 0) {
        fail('GRADING_UNAVAILABLE', 'Grading is not available right now; it will be retried', HttpStatus.SERVICE_UNAVAILABLE, {
          reason: err.code,
        });
      }
      if (err.status === 422) fail('GRADING_FAILED', err.message, HttpStatus.UNPROCESSABLE_ENTITY, { reason: err.code, ...err.details });
      fail('GRADING_ERROR', 'Grading failed', HttpStatus.BAD_GATEWAY, { reason: err.code });
    }

    const saved = await this.prisma.$transaction(async (tx) => {
      const row = await tx.qualityGrade.create({
        data: {
          batchId,
          grade: result.grade,
          defects: result.defects as unknown as Prisma.InputJsonValue,
          confidence: result.confidence,
          modelVersion: result.modelVersion,
          source: 'AUTO',
        },
      });
      await tx.batch.update({
        where: { id: batchId },
        data: { currentGrade: result.grade, ...(batch.status === 'REGISTERED' ? { status: 'GRADED' } : {}) },
      });
      await this.trace.append(
        tx,
        batchId,
        'GRADED',
        {
          grade: result.grade,
          confidence: result.confidence,
          modelVersion: result.modelVersion,
          defectClasses: [...new Set(result.defects.map((d) => d.class))].sort(),
          gradeId: row.id,
        },
        user.id,
      );
      return row;
    });

    await this.events.publish('quality-scans', batchId, { type: 'GRADED', batchId, grade: result.grade, modelVersion: result.modelVersion });
    await this.afterGradeChange(batchId, 'GRADE', user.id);
    const storagePath = await this.batches.storagePath(user, batchId);
    return { ...view(saved), mlLatencyMs: result.latencyMs, totalLatencyMs: Date.now() - started, storagePath };
  }

  /** FO-FR-07 dispute: flags the latest grade for a manager. */
  async dispute(user: AuthUser, batchId: string, reason: string) {
    const batch = await this.batches.loadForUser(user, batchId);
    Ownership.assertSite(user, batch.currentSiteId);
    const latest = await this.prisma.qualityGrade.findFirst({ where: { batchId }, orderBy: { createdAt: 'desc' } });
    if (!latest) fail('NO_GRADE', 'This batch has not been graded yet', HttpStatus.CONFLICT);
    if (latest.disputed) fail('ALREADY_DISPUTED', 'This grade is already disputed', HttpStatus.CONFLICT);
    const updated = await this.prisma.$transaction(async (tx) => {
      const flipped = await tx.qualityGrade.updateMany({ where: { id: latest.id, disputed: false }, data: { disputed: true, disputeReason: reason } });
      if (flipped.count !== 1) fail('ALREADY_DISPUTED', 'This grade is already disputed', HttpStatus.CONFLICT);
      await this.trace.append(tx, batchId, 'GRADE_DISPUTED', { gradeId: latest.id, grade: latest.grade, reason }, user.id);
      return tx.qualityGrade.findUniqueOrThrow({ where: { id: latest.id } });
    });
    return view(updated);
  }

  /** Manager decides a disputed grade. The decision is a new MANUAL grade row; the AUTO row is kept. */
  async resolve(user: AuthUser, gradeId: string, grade: Grade) {
    const disputed = await this.prisma.qualityGrade.findUnique({ where: { id: gradeId } });
    if (!disputed) fail('NOT_FOUND', 'Grade not found', HttpStatus.NOT_FOUND);
    if (!disputed.disputed) fail('NOT_DISPUTED', 'Only disputed grades can be resolved', HttpStatus.CONFLICT);
    const manual = await this.prisma.$transaction(async (tx) => {
      const flipped = await tx.qualityGrade.updateMany({ where: { id: gradeId, resolvedBy: null }, data: { resolvedBy: user.id } });
      if (flipped.count !== 1) fail('ALREADY_RESOLVED', 'This dispute was already resolved', HttpStatus.CONFLICT);
      const row = await tx.qualityGrade.create({
        data: { batchId: disputed.batchId, grade, defects: [], confidence: 1, modelVersion: 'manual', source: 'MANUAL', resolvedBy: user.id },
      });
      await tx.batch.update({ where: { id: disputed.batchId }, data: { currentGrade: grade } });
      await this.trace.append(tx, disputed.batchId, 'GRADE_RESOLVED', { gradeId, previous: disputed.grade, grade, manualGradeId: row.id }, user.id);
      return row;
    });
    await this.afterGradeChange(disputed.batchId, 'MANUAL', user.id);
    return view(manual);
  }

  /** Approvals screen (M13): open disputes first. */
  async disputes(q: PageQuery) {
    const limit = q.limit ?? 20;
    const open: Prisma.QualityGradeWhereInput = { disputed: true, resolvedBy: null };
    const rows = await this.prisma.qualityGrade.findMany({
      where: { AND: [open, afterCursor(q.cursor) as Prisma.QualityGradeWhereInput] },
      include: { batch: { select: { code: true, currentSiteId: true } } },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
    });
    const page = toPage(rows, limit);
    return { items: page.items.map(view), nextCursor: page.nextCursor };
  }

  /** The grade changes the shelf-life estimate; a failure here must not undo the grade. */
  private async afterGradeChange(batchId: string, trigger: 'GRADE' | 'MANUAL', actorId: string) {
    try {
      await this.shelfLife.recompute(batchId, trigger, actorId);
    } catch (e) {
      this.logger.error({ msg: 'shelf-life recompute after grade failed', batchId, error: (e as Error).message });
    }
  }
}
