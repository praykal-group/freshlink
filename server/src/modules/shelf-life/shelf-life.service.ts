import { Injectable, Logger } from '@nestjs/common';
import type { Prisma, ShelfLifeMethod, ShelfLifeTrigger } from '@prisma/client';
import { MlCallError, MlClient } from '../../infra/ml/ml-client.service';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { TraceService } from '../trace/trace.service';
import { CargoStatusNotifier } from './cargo-status.notifier';
import { BACKEND_Q10_VERSION, isSignificantChange, q10RemainingH, refTempOf } from './q10';

interface MlShelfLifeResult {
  batchId: string;
  remainingH: number;
  survivalCurve: { h: number; p: number }[];
  method: ShelfLifeMethod;
  modelVersion: string;
  censored?: boolean;
}

const DONE: string[] = ['DELIVERED', 'REJECTED', 'SPOILED'];
/** SYN-04: the recompute after a threshold breach must finish within 5 s end to end. */
const ML_TIMEOUT_MS = 2500;

/** Residual shelf life per batch (SYN-04, ML-02): estimate history + current value on the batch. */
@Injectable()
export class ShelfLifeService {
  private readonly logger = new Logger(ShelfLifeService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly ml: MlClient,
    private readonly trace: TraceService,
    private readonly cargo: CargoStatusNotifier,
  ) {}

  /**
   * Recomputes and stores the estimate. Never throws because of the ML service: when it is down
   * the backend Q10 copy answers. Returns null for batches that are finished.
   */
  async recompute(batchId: string, trigger: ShelfLifeTrigger, actorUserId: string | null = null) {
    const batch = await this.prisma.batch.findUnique({ where: { id: batchId }, include: { product: true, exposure: true } });
    if (!batch || DONE.includes(batch.status)) return null;

    const p = batch.product;
    const refTempC = refTempOf(Number(p.safeTempMin), Number(p.safeTempMax));
    const ex = batch.exposure;
    const input = {
      batchId,
      productCode: p.code,
      category: p.category,
      grade: batch.currentGrade ?? undefined,
      hoursSinceHarvest: Math.max(0, (Date.now() - batch.caughtOrHarvestedAt.getTime()) / 3_600_000),
      // Until telemetry exists (M8) a batch is assumed to have been held at its reference temperature.
      meanTempC: ex?.meanTemp !== null && ex?.meanTemp !== undefined ? Number(ex.meanTemp) : refTempC,
      degreeMinutesAbove: ex ? Number(ex.degreeMinutesAbove) : 0,
      ethylenePpm: ex?.maxEthylenePpm !== null && ex?.maxEthylenePpm !== undefined ? Number(ex.maxEthylenePpm) : undefined,
      shockEvents: ex?.shockEvents ?? 0,
      baseShelfLifeH: Number(p.baseShelfLifeH),
      q10: Number(p.q10),
      refTempC,
    };

    let result: MlShelfLifeResult;
    try {
      const res = await this.ml.post<{ results: MlShelfLifeResult[] }>('/v1/shelf-life/predict', { items: [input] }, ML_TIMEOUT_MS);
      result = res.results[0];
    } catch (e) {
      const err = e as MlCallError;
      this.logger.warn({ msg: 'ML shelf-life unavailable, using backend Q10', status: err.status, code: err.code });
      result = {
        batchId,
        remainingH: q10RemainingH(input),
        survivalCurve: [],
        method: 'Q10_FALLBACK',
        modelVersion: BACKEND_Q10_VERSION,
      };
    }

    const previous = batch.remainingShelfLifeH === null ? null : Number(batch.remainingShelfLifeH);
    const now = new Date();
    const estimate = await this.prisma.$transaction(async (tx) => {
      const row = await tx.shelfLifeEstimate.create({
        data: {
          batchId,
          remainingH: result.remainingH,
          survivalCurve: result.survivalCurve as unknown as Prisma.InputJsonValue,
          method: result.method,
          modelVersion: result.modelVersion,
          trigger,
        },
      });
      await tx.batch.update({ where: { id: batchId }, data: { remainingShelfLifeH: result.remainingH, shelfLifeUpdatedAt: now } });
      if (isSignificantChange(previous, result.remainingH)) {
        await this.trace.append(
          tx,
          batchId,
          'SHELF_LIFE_UPDATED',
          { remainingH: result.remainingH, previousH: previous, method: result.method, modelVersion: result.modelVersion, trigger },
          actorUserId,
          now,
        );
      }
      return row;
    });

    await this.cargo.batchUpdated({ batchId, remainingShelfLifeH: result.remainingH, method: result.method, trigger });
    return { ...estimate, remainingH: Number(estimate.remainingH) };
  }
}
