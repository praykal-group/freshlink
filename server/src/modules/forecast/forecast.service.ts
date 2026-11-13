import { HttpStatus, Injectable, Logger } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { AppError } from '../../common/errors/app-error';
import { MlCallError, MlClient } from '../../infra/ml/ml-client.service';
import { PrismaService } from '../../infra/prisma/prisma.service';

interface MlForecastRow {
  siteId: string;
  productId: string;
  date: string;
  predictedKg: number;
  lowerKg: number;
  upperKg: number;
  historySource: 'PROVIDED' | 'SIMULATED';
}

interface MlForecastResponse {
  runId: string;
  rows: MlForecastRow[];
  modelVersion: string;
  method: string;
  latencyMs: number;
}

export interface RunOptions {
  startDate?: string; // YYYY-MM-DD (IST day); default tomorrow
  siteIds?: string[];
  productIds?: string[];
}

export interface RunSummary {
  runId: string;
  startDate: string;
  sites: number;
  products: number;
  rows: number;
  modelVersion: string;
  method: string;
  mlLatencyMs: number;
}

export type JobState =
  | { id: string; status: 'RUNNING'; startedAt: string }
  | { id: string; status: 'DONE'; startedAt: string; finishedAt: string; result: RunSummary }
  | { id: string; status: 'FAILED'; startedAt: string; finishedAt: string; error: string };

const ML_TIMEOUT_MS = 60_000;
const MAX_JOBS_KEPT = 50;

/** Tomorrow's date in India time. */
export function istTomorrow(now = new Date()): string {
  const ist = new Date(now.getTime() + 5.5 * 3_600_000);
  ist.setUTCDate(ist.getUTCDate() + 1);
  return ist.toISOString().slice(0, 10);
}

/** For each (site, product, date) keep the row of the newest run. Rows must be sorted newest first. */
export function latestPerDay<T extends { siteId: string; productId: string; forecastDate: Date }>(rowsNewestFirst: T[]): T[] {
  const seen = new Set<string>();
  const out: T[] = [];
  for (const r of rowsNewestFirst) {
    const key = `${r.siteId}|${r.productId}|${r.forecastDate.toISOString().slice(0, 10)}`;
    if (!seen.has(key)) {
      seen.add(key);
      out.push(r);
    }
  }
  return out.sort((a, b) => a.forecastDate.getTime() - b.forecastDate.getTime() || a.siteId.localeCompare(b.siteId) || a.productId.localeCompare(b.productId));
}

/** 7-day demand forecast per distribution centre × product (SYN-11, W-3 step 1). */
@Injectable()
export class ForecastService {
  private readonly logger = new Logger(ForecastService.name);
  private readonly jobs = new Map<string, JobState>();
  private running = false;

  constructor(
    private readonly prisma: PrismaService,
    private readonly ml: MlClient,
  ) {}

  async run(opts: RunOptions = {}): Promise<RunSummary> {
    const startDate = opts.startDate ?? istTomorrow();
    const [sites, products] = await Promise.all([
      this.prisma.site.findMany({
        where: { active: true, type: 'DISTRIBUTION_CENTRE', ...(opts.siteIds?.length ? { id: { in: opts.siteIds } } : {}) },
        select: { id: true, lat: true, lng: true },
      }),
      this.prisma.product.findMany({
        where: { active: true, ...(opts.productIds?.length ? { id: { in: opts.productIds } } : {}) },
        select: { id: true },
      }),
    ]);
    if (!sites.length || !products.length) {
      throw new AppError('NOTHING_TO_FORECAST', 'No active distribution centres or products match', HttpStatus.UNPROCESSABLE_ENTITY);
    }

    let res: MlForecastResponse;
    try {
      res = await this.ml.post<MlForecastResponse>(
        '/v1/forecast/run',
        {
          siteIds: sites.map((s) => s.id),
          productIds: products.map((p) => p.id),
          startDate,
          horizonDays: 7,
          // No sales table yet: the ML service uses its simulated history (Section 2, D-70).
          siteCoords: Object.fromEntries(sites.map((s) => [s.id, { lat: s.lat, lng: s.lng }])),
        },
        ML_TIMEOUT_MS,
      );
    } catch (e) {
      const err = e as MlCallError;
      throw new AppError('FORECAST_UNAVAILABLE', `Forecast service failed: ${err.code}`, HttpStatus.SERVICE_UNAVAILABLE, { status: err.status });
    }

    const runId = res.runId || randomUUID();
    const { count } = await this.prisma.demandForecast.createMany({
      data: res.rows.map((r) => ({
        siteId: r.siteId,
        productId: r.productId,
        forecastDate: new Date(`${r.date}T00:00:00Z`),
        predictedKg: r.predictedKg,
        lowerKg: r.lowerKg,
        upperKg: r.upperKg,
        modelVersion: res.modelVersion,
        runId,
      })),
      skipDuplicates: true,
    });
    const summary = {
      runId,
      startDate,
      sites: sites.length,
      products: products.length,
      rows: count,
      modelVersion: res.modelVersion,
      method: res.method,
      mlLatencyMs: res.latencyMs,
    };
    this.logger.log({ msg: 'forecast stored', ...summary });
    return summary;
  }

  /** POST /forecasts/run: start in the background, poll GET /forecasts/jobs/:id. One run at a time. */
  start(opts: RunOptions): JobState {
    if (this.running) throw new AppError('FORECAST_RUNNING', 'A forecast run is already in progress', HttpStatus.CONFLICT);
    const id = randomUUID();
    const startedAt = new Date().toISOString();
    const job: JobState = { id, status: 'RUNNING', startedAt };
    this.remember(job);
    this.running = true;
    this.run(opts)
      .then((result) => this.remember({ id, status: 'DONE', startedAt, finishedAt: new Date().toISOString(), result }))
      .catch((e: Error) => this.remember({ id, status: 'FAILED', startedAt, finishedAt: new Date().toISOString(), error: e.message }))
      .finally(() => {
        this.running = false;
      });
    return job;
  }

  job(id: string): JobState {
    const j = this.jobs.get(id);
    if (!j) throw new AppError('NOT_FOUND', 'Forecast job not found', HttpStatus.NOT_FOUND);
    return j;
  }

  private remember(job: JobState) {
    this.jobs.set(job.id, job);
    while (this.jobs.size > MAX_JOBS_KEPT) this.jobs.delete(this.jobs.keys().next().value as string);
  }

  /** GET /forecasts: newest run's value per (site, product, day) in [from, to]. */
  async query(q: { siteId?: string; productId?: string; from: string; to: string }) {
    const rows = await this.prisma.demandForecast.findMany({
      where: {
        ...(q.siteId ? { siteId: q.siteId } : {}),
        ...(q.productId ? { productId: q.productId } : {}),
        forecastDate: { gte: new Date(`${q.from}T00:00:00Z`), lte: new Date(`${q.to}T00:00:00Z`) },
      },
      orderBy: { createdAt: 'desc' },
      take: 20_000,
    });
    return latestPerDay(rows).map((r) => ({
      siteId: r.siteId,
      productId: r.productId,
      date: r.forecastDate.toISOString().slice(0, 10),
      predictedKg: Number(r.predictedKg),
      lowerKg: Number(r.lowerKg),
      upperKg: Number(r.upperKg),
      modelVersion: r.modelVersion,
      runId: r.runId,
    }));
  }
}
