import { Inject, Injectable, Logger, OnApplicationBootstrap } from '@nestjs/common';
import type Redis from 'ioredis';
import type { EachBatchPayload } from 'kafkajs';
import { KafkaService } from '../../infra/kafka/kafka.service';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { REDIS } from '../../infra/redis/redis.module';
import { DeviceContextService } from '../../modules/telemetry/device-context.service';
import { REDIS_KEYS, type TelemetryMessage } from '../../modules/telemetry/telemetry-message';
import { accumulate, emptyExposure, type Exposure, meanTemp } from '../../modules/telemetry/thresholds';

/**
 * Consumer group `exposure-aggregator` (Section 9.3): running exposure per batch on board in
 * Redis; `flush()` (every 5 min, maintenance job) writes it to `batch_exposure`, which the shelf-life
 * model reads (degree-minutes above the limit, mean/max temp, shocks, peak ethylene).
 */
@Injectable()
export class ExposureAggregator implements OnApplicationBootstrap {
  private readonly logger = new Logger(ExposureAggregator.name);

  constructor(
    private readonly kafka: KafkaService,
    private readonly context: DeviceContextService,
    private readonly prisma: PrismaService,
    @Inject(REDIS) private readonly redis: Redis,
  ) {}

  async onApplicationBootstrap() {
    await this.kafka.consume('exposure-aggregator', 'truck-telemetry', (b) => this.handle(b));
  }

  async handle({ batch, resolveOffset, heartbeat }: EachBatchPayload) {
    for (const m of batch.messages) {
      try {
        const msg = JSON.parse(m.value?.toString('utf8') ?? 'null') as TelemetryMessage | null;
        if (msg?.tripId) await this.process(msg);
      } catch (e) {
        this.logger.warn({ msg: 'exposure message skipped', offset: m.offset, error: (e as Error).message });
      }
      resolveOffset(m.offset);
      await heartbeat();
    }
  }

  async process(m: TelemetryMessage) {
    const cargo = await this.context.tripCargo(m.tripId as string);
    if (!cargo) return;
    const ts = Date.parse(m.ts);
    const prevRaw = await this.redis.hget(REDIS_KEYS.prevTs, m.deviceCode);
    const prevTs = prevRaw === null ? null : Number(prevRaw);
    if (prevTs !== null && ts <= prevTs) return; // duplicate or out-of-order replay: already counted
    const reading = { ts, tempC: m.tempC, humidityPct: m.humidityPct, shockG: m.shockG, ethylenePpm: m.ethylenePpm };
    const pipe = this.redis.pipeline();
    for (const b of cargo.batches) {
      const key = REDIS_KEYS.exposure(b.batchId);
      const cur = JSON.parse((await this.redis.get(key)) ?? 'null') as Exposure | null;
      pipe.set(key, JSON.stringify(accumulate(cur ?? emptyExposure(), reading, prevTs, b.safeTempMax, b.shockMaxG)), 'EX', 30 * 86_400);
      pipe.sadd(REDIS_KEYS.exposureDirty, b.batchId);
    }
    pipe.hset(REDIS_KEYS.prevTs, m.deviceCode, String(ts));
    await pipe.exec();
  }

  /** Writes every changed batch's totals to batch_exposure. */
  async flush(): Promise<number> {
    const ids = await this.redis.spop(REDIS_KEYS.exposureDirty, 1000);
    for (const batchId of ids) {
      const e = JSON.parse((await this.redis.get(REDIS_KEYS.exposure(batchId))) ?? 'null') as Exposure | null;
      if (!e) continue;
      const data = {
        degreeMinutesAbove: round(e.degreeMinutesAbove),
        minutesAboveLimit: Math.round(e.minutesAboveLimit),
        meanTemp: meanTemp(e) === null ? null : round(meanTemp(e) as number, 2),
        maxTemp: e.maxTemp,
        shockEvents: e.shockEvents,
        maxEthylenePpm: e.maxEthylenePpm,
      };
      await this.prisma.batchExposure.upsert({ where: { batchId }, update: data, create: { batchId, ...data } }).catch((err: Error) => {
        this.logger.error({ msg: 'exposure upsert failed', batchId, error: err.message });
        return this.redis.sadd(REDIS_KEYS.exposureDirty, batchId); // retry next flush
      });
    }
    return ids.length;
  }
}

const round = (v: number, d = 3) => Math.round(v * 10 ** d) / 10 ** d;
