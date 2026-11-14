import { Inject, Injectable, Logger, OnApplicationBootstrap, OnApplicationShutdown } from '@nestjs/common';
import { type Job, type Queue, Worker } from 'bullmq';
import type Redis from 'ioredis';
import { minutesToMs } from '../../common/time-scale';
import { AppConfig } from '../../config/config.service';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { bullConnection, MAINTENANCE_QUEUE, QUEUE_ALERTS, QUEUE_MAINTENANCE } from '../../infra/queue/queues';
import { REDIS, requireEnv } from '../../infra/redis/redis.module';
import { AlertsService, ESCALATION_JOB } from '../../modules/alerts/alerts.service';
import { ReroutingService, ROUTE_RESPONSE_JOB } from '../../modules/diversions/rerouting.service';
import { IncidentsService } from '../../modules/incidents/incidents.service';
import { ForecastService } from '../../modules/forecast/forecast.service';
import { ShelfLifeService } from '../../modules/shelf-life/shelf-life.service';
import { REDIS_KEYS } from '../../modules/telemetry/telemetry-message';
import { ExposureAggregator } from '../consumers/exposure-aggregator';
import { DRIVER_FIX_RECHECK_JOB, driverFixRecheck } from './driver-fix-recheck.job';
import { OFFER_TIMEOUT_JOB, offerTimeout } from './offer-timeout.job';
import { ReeferHealthJob } from './reefer-health.job';
import { TieringJob } from './tiering';

/** Batches whose shelf life still matters (refreshed every 15 min, D-06). */
const LIVE_BATCH = ['REGISTERED', 'GRADED', 'STORED', 'ALLOCATED', 'LOADED', 'IN_TRANSIT', 'DIVERTED'] as const;
const IST = 'Asia/Kolkata';

/**
 * BullMQ workers in the worker process:
 *   alerts queue       → alert-escalation (DA-FR-07), offer-timeout (W-1), driver-fix-recheck (W-2),
 *                        route-response (driver did not answer a reroute) — all delayed jobs
 *   maintenance queue  → device-offline (1 min), exposure-flush (5 min), shelf-life-refresh (15 min),
 *                        telemetry-tiering (01:00 IST), forecast-nightly (02:00 IST),
 *                        reefer-health (Mondays 03:00 IST, SYN-17)
 * Intervals in minutes go through TELEMETRY_TIME_SCALE (tests only); the daily crons do not.
 */
@Injectable()
export class MaintenanceWorker implements OnApplicationBootstrap, OnApplicationShutdown {
  private readonly logger = new Logger(MaintenanceWorker.name);
  private readonly workers: Worker[] = [];

  constructor(
    private readonly config: AppConfig,
    private readonly prisma: PrismaService,
    private readonly alerts: AlertsService,
    private readonly shelfLife: ShelfLifeService,
    private readonly forecasts: ForecastService,
    private readonly exposure: ExposureAggregator,
    private readonly tiering: TieringJob,
    private readonly incidents: IncidentsService,
    private readonly rerouting: ReroutingService,
    private readonly reeferHealth: ReeferHealthJob,
    @Inject(MAINTENANCE_QUEUE) private readonly maintenance: Queue,
    @Inject(REDIS) private readonly redis: Redis,
  ) {}

  async onApplicationBootstrap() {
    const connection = bullConnection(requireEnv(this.config.get('REDIS_URL'), 'REDIS_URL'));
    this.workers.push(
      new Worker(QUEUE_ALERTS, (job) => this.onAlertJob(job), { connection, concurrency: 5 }),
      new Worker(QUEUE_MAINTENANCE, (job) => this.onMaintenanceJob(job), { connection, concurrency: 2 }),
    );
    for (const w of this.workers) w.on('failed', (job, err) => this.logger.error({ msg: 'job failed', queue: w.name, job: job?.name, error: err.message }));

    // Idempotent: re-registering on restart replaces the schedule instead of adding a second one.
    const every = (id: string, minutes: number) => this.maintenance.upsertJobScheduler(id, { every: minutesToMs(minutes) }, { name: id });
    const cron = (id: string, pattern: string) => this.maintenance.upsertJobScheduler(id, { pattern, tz: IST }, { name: id });
    await every('device-offline', 1);
    await every('exposure-flush', 5);
    await every('shelf-life-refresh', 15);
    await cron('telemetry-tiering', '0 1 * * *');
    await cron('forecast-nightly', '0 2 * * *');
    await cron('reefer-health', '0 3 * * 1');
    this.logger.log('maintenance schedules registered');
  }

  async onApplicationShutdown() {
    await Promise.all(this.workers.map((w) => w.close()));
  }

  private async onAlertJob(job: Job) {
    switch (job.name) {
      case ESCALATION_JOB:
        return { escalated: await this.alerts.escalate((job.data as { alertId: string }).alertId) };
      case OFFER_TIMEOUT_JOB:
        return offerTimeout(job, this.incidents);
      case DRIVER_FIX_RECHECK_JOB:
        return driverFixRecheck(job, this.incidents);
      case ROUTE_RESPONSE_JOB: {
        const { tripId, version } = job.data as { tripId: string; version: number };
        return { escalated: await this.rerouting.responseTimeout(tripId, version) };
      }
      default:
        this.logger.warn({ msg: 'unknown alerts job', name: job.name });
        return null;
    }
  }

  private async onMaintenanceJob(job: Job) {
    switch (job.name) {
      case 'device-offline':
        return { raised: await this.checkOffline() };
      case 'exposure-flush':
        return { flushed: await this.exposure.flush() };
      case 'shelf-life-refresh':
        return { refreshed: await this.refreshShelfLife() };
      case 'telemetry-tiering':
        return this.tiering.run();
      case 'forecast-nightly':
        return this.forecasts.run();
      case 'reefer-health':
        return this.reeferHealth.run();
      default:
        this.logger.warn({ msg: 'unknown maintenance job', name: job.name });
        return null;
    }
  }

  /** Section 6.5: no packet for 5 min from a truck on an active trip → DEVICE_OFFLINE WARNING (once per outage). */
  async checkOffline(now = Date.now()): Promise<number> {
    const limit = minutesToMs(5);
    const devices = await this.prisma.iotDevice.findMany({
      where: { status: 'ACTIVE', vehicle: { trips: { some: { status: 'IN_PROGRESS' } } } },
      select: { deviceCode: true, vehicleId: true, vehicle: { select: { trips: { where: { status: 'IN_PROGRESS' }, select: { id: true, code: true, startedAt: true } } } } },
    });
    let raised = 0;
    for (const d of devices) {
      const trip = d.vehicle?.trips[0];
      if (!trip) continue;
      const seen = Number((await this.redis.hget(REDIS_KEYS.lastSeen, d.deviceCode)) ?? 0);
      const since = Math.max(seen, trip.startedAt?.getTime() ?? 0); // a trip that just started gets 5 min grace
      if (now - since < limit) continue;
      if (!(await this.redis.sadd(REDIS_KEYS.offline, d.deviceCode))) continue; // already alerted
      await this.alerts.raise({
        type: 'DEVICE_OFFLINE',
        severity: 'WARNING',
        tripId: trip.id,
        vehicleId: d.vehicleId,
        message: `No data from ${d.deviceCode} on trip ${trip.code} since ${seen ? new Date(seen).toISOString() : 'trip start'}; phone GPS continues the position`,
        data: { deviceCode: d.deviceCode, lastSeen: seen || null },
      });
      raised++;
    }
    return raised;
  }

  private async refreshShelfLife(): Promise<number> {
    const batches = await this.prisma.batch.findMany({ where: { status: { in: [...LIVE_BATCH] } }, select: { id: true } });
    let done = 0;
    for (let i = 0; i < batches.length; i += 5) {
      const results = await Promise.allSettled(batches.slice(i, i + 5).map((b) => this.shelfLife.recompute(b.id, 'SCHEDULED')));
      done += results.filter((r) => r.status === 'fulfilled').length;
    }
    return done;
  }
}
