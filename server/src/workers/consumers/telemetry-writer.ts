import { Inject, Injectable, Logger, OnApplicationBootstrap } from '@nestjs/common';
import type Redis from 'ioredis';
import type { EachBatchPayload } from 'kafkajs';
import { InfluxService, Point } from '../../infra/influx/influx.service';
import { KafkaService } from '../../infra/kafka/kafka.service';
import { REDIS } from '../../infra/redis/redis.module';
import { RealtimeService } from '../../modules/realtime/realtime.service';
import { REDIS_KEYS, type TelemetryMessage } from '../../modules/telemetry/telemetry-message';

/** Only live packets count towards the latency metric (burst replays after a dropout are old by design). */
const LIVE_MS = 10_000;
const LATENCY_SAMPLES = 5000;

export function toPoint(m: TelemetryMessage): Point {
  const p = new Point('reefer').tag('device_id', m.deviceCode).timestamp(new Date(m.ts)).floatField('temp_c', m.tempC);
  if (m.vehicleId) p.tag('vehicle_id', m.vehicleId);
  if (m.tripId) p.tag('trip_id', m.tripId);
  const f = (name: string, v: number | null) => {
    if (v !== null) p.floatField(name, v);
  };
  f('humidity_pct', m.humidityPct);
  f('ax', m.ax);
  f('ay', m.ay);
  f('az', m.az);
  f('shock_g', m.shockG);
  f('ethylene_ppm', m.ethylenePpm);
  f('setpoint_c', m.setpointC);
  f('battery_pct', m.batteryPct);
  f('lat', m.lat);
  f('lng', m.lng);
  if (m.reeferOn !== null) p.booleanField('reefer_on', m.reeferOn);
  if (m.doorOpen !== null) p.booleanField('door_open', m.doorOpen);
  if (m.seq !== null) p.intField('seq', m.seq);
  return p;
}

/**
 * Consumer group `telemetry-writer` → InfluxDB `reefer` (Section 9.3). Offsets are committed only
 * after the batch is flushed, so a crash replays rather than loses points (same tags + time =
 * the same point, so replays are idempotent). Records sensor→Influx latency (SRV-02).
 */
@Injectable()
export class TelemetryWriter implements OnApplicationBootstrap {
  private readonly logger = new Logger(TelemetryWriter.name);

  constructor(
    private readonly kafka: KafkaService,
    private readonly influx: InfluxService,
    private readonly realtime: RealtimeService,
    @Inject(REDIS) private readonly redis: Redis,
  ) {}

  async onApplicationBootstrap() {
    await this.kafka.consume('telemetry-writer', 'truck-telemetry', (b) => this.handle(b));
  }

  async handle({ batch, resolveOffset, heartbeat }: EachBatchPayload) {
    const messages: TelemetryMessage[] = [];
    for (const m of batch.messages) {
      try {
        messages.push(JSON.parse(m.value?.toString('utf8') ?? 'null'));
      } catch {
        this.logger.warn({ msg: 'unparseable kafka message skipped', offset: m.offset });
      }
    }
    if (messages.length) {
      await this.influx.writeNow(messages.map(toPoint));
      const now = Date.now();
      const pipe = this.redis.pipeline();
      for (const m of messages) {
        const ts = Date.parse(m.ts);
        const received = Date.parse(m.receivedAt);
        if (now - received < LIVE_MS) {
          pipe.lpush(REDIS_KEYS.latencyWrite, String(now - ts));
          pipe.lpush(REDIS_KEYS.latencyBridgeWrite, String(now - received));
        }
        if (m.vehicleId) pipe.set(REDIS_KEYS.lastReading(m.vehicleId), JSON.stringify(m), 'EX', 3600);
      }
      pipe.ltrim(REDIS_KEYS.latencyWrite, 0, LATENCY_SAMPLES - 1);
      pipe.ltrim(REDIS_KEYS.latencyBridgeWrite, 0, LATENCY_SAMPLES - 1);
      pipe.incrby(REDIS_KEYS.counter('written'), messages.length);
      await pipe.exec();
      // Live map (Section 10.6): latest position per vehicle.
      for (const m of messages) {
        if (m.vehicleId && m.lat !== null && m.lng !== null) {
          this.realtime.toManagers('vehicle.position', { vehicleId: m.vehicleId, tripId: m.tripId, lat: m.lat, lng: m.lng, tempC: m.tempC, at: m.ts });
        }
      }
    }
    resolveOffset(batch.messages[batch.messages.length - 1].offset);
    await heartbeat();
  }
}
