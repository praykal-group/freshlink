import { Inject, Injectable, Logger, OnApplicationBootstrap } from '@nestjs/common';
import type Redis from 'ioredis';
import type { EachBatchPayload } from 'kafkajs';
import { minutesToMs } from '../../common/time-scale';
import { KafkaService } from '../../infra/kafka/kafka.service';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { REDIS } from '../../infra/redis/redis.module';
import { AlertsService } from '../../modules/alerts/alerts.service';
import { RealtimeService } from '../../modules/realtime/realtime.service';
import { RemoteConfigService } from '../../modules/remote-config/remote-config.service';
import { ShelfLifeService } from '../../modules/shelf-life/shelf-life.service';
import { DeviceContextService, type TripCargo } from '../../modules/telemetry/device-context.service';
import { REDIS_KEYS, type TelemetryMessage } from '../../modules/telemetry/telemetry-message';
import { type Action, type BreachState, evaluate } from '../../modules/telemetry/thresholds';
import { TraceService } from '../../modules/trace/trace.service';

const LATENCY_SAMPLES = 2000;
const SHOCK_COOLDOWN_MIN = 10;

const LABEL: Record<string, string> = { temp: 'Temperature', humidity: 'Humidity', ethylene: 'Ethylene', shock: 'Shock' };
const UNIT: Record<string, string> = { temp: '°C', humidity: '%', ethylene: 'ppm', shock: 'g' };

/**
 * Consumer group `threshold-processor` (Section 6.5, SYN-04/07/18). Per device: load the breach
 * state from Redis, run the pure rule engine, save the state, then act:
 *   BREACH_START → shelf-life recompute for the batches on board (target ≤ 5 s)
 *   RAISE        → alert (+ notifications, + escalation for critical) and an EXCURSION trace event
 * Kafka keys by device, so one device's packets are processed in order.
 */
@Injectable()
export class ThresholdProcessor implements OnApplicationBootstrap {
  private readonly logger = new Logger(ThresholdProcessor.name);

  constructor(
    private readonly kafka: KafkaService,
    private readonly context: DeviceContextService,
    private readonly alerts: AlertsService,
    private readonly shelfLife: ShelfLifeService,
    private readonly trace: TraceService,
    private readonly config: RemoteConfigService,
    private readonly realtime: RealtimeService,
    private readonly prisma: PrismaService,
    @Inject(REDIS) private readonly redis: Redis,
  ) {}

  async onApplicationBootstrap() {
    await this.kafka.consume('threshold-processor', 'truck-telemetry', (b) => this.handle(b));
  }

  async handle({ batch, resolveOffset, heartbeat }: EachBatchPayload) {
    const persistMs = minutesToMs(await this.config.get('persistMinutes'));
    for (const m of batch.messages) {
      let msg: TelemetryMessage | null = null;
      try {
        msg = JSON.parse(m.value?.toString('utf8') ?? 'null');
      } catch {
        /* skipped below */
      }
      if (msg?.tripId) await this.process(msg, persistMs);
      resolveOffset(m.offset);
      await heartbeat();
    }
  }

  async process(m: TelemetryMessage, persistMs: number) {
    const cargo = await this.context.tripCargo(m.tripId as string);
    if (!cargo?.limits) return;
    const key = REDIS_KEYS.breach(m.deviceCode);
    const prev = JSON.parse((await this.redis.get(key)) ?? '{}') as BreachState;
    const ts = Date.parse(m.ts);
    const { state, actions } = evaluate(
      { ts, tempC: m.tempC, humidityPct: m.humidityPct, shockG: m.shockG, ethylenePpm: m.ethylenePpm },
      cargo.limits,
      prev,
      { persistMs, shockCooldownMs: minutesToMs(SHOCK_COOLDOWN_MIN) },
    );
    await this.redis.set(key, JSON.stringify(state), 'EX', 7 * 86_400);

    // DA-FR-05: live cargo strip on the driver phone.
    this.realtime.toTrip(cargo.tripId, 'cargo.status', {
      tripId: cargo.tripId, tempC: m.tempC, humidityPct: m.humidityPct, ethylenePpm: m.ethylenePpm, at: m.ts,
      breach: { temp: state.tempStart !== undefined, humidity: state.humStart !== undefined, ethylene: !!state.ethAlerted },
    });

    for (const a of actions) {
      try {
        await this.act(a, m, cargo, ts);
      } catch (e) {
        this.logger.error({ msg: 'threshold action failed', action: a.kind, metric: a.metric, deviceCode: m.deviceCode, error: (e as Error).message });
      }
    }
  }

  private async act(a: Action, m: TelemetryMessage, cargo: TripCargo, ts: number) {
    if (a.kind === 'BREACH_START') {
      // SYN-04: recompute right away; latency measured from the sensor timestamp.
      await Promise.all(cargo.batches.map((b) => this.shelfLife.recompute(b.batchId, 'BREACH')));
      await this.redis.lpush(REDIS_KEYS.latencyShelf, String(Date.now() - ts));
      await this.redis.ltrim(REDIS_KEYS.latencyShelf, 0, LATENCY_SAMPLES - 1);
      return;
    }
    if (a.kind === 'RECOVERED') {
      this.logger.log({ msg: 'breach recovered', metric: a.metric, deviceCode: m.deviceCode, durationMs: a.durationMs });
      return;
    }
    const minutes = Math.round(a.sinceMs / 60_000);
    const message =
      `${LABEL[a.metric]} ${a.value}${UNIT[a.metric]} beyond limit ${a.limit}${UNIT[a.metric]} on trip ${cargo.code}` +
      (a.metric === 'temp' || a.metric === 'humidity' ? ` (for ${minutes} min)` : '');
    await this.alerts.raise({
      type: a.type,
      severity: a.severity,
      tripId: cargo.tripId,
      vehicleId: cargo.vehicleId,
      message,
      data: { metric: a.metric, value: a.value, limit: a.limit, sinceMs: a.sinceMs, deviceCode: m.deviceCode, at: m.ts },
      notifyDriver: a.severity === 'CRITICAL',
    });
    if (a.metric === 'temp' || a.metric === 'ethylene') {
      for (const b of cargo.batches) {
        await this.prisma.$transaction((tx) =>
          this.trace.append(tx, b.batchId, 'EXCURSION', { metric: a.metric, value: a.value, limit: a.limit, tripCode: cargo.code, sinceMinutes: minutes }, null, new Date(ts)),
        );
      }
    }
  }
}
