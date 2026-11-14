import { Inject, Injectable, Logger, OnApplicationBootstrap, OnApplicationShutdown } from '@nestjs/common';
import type Redis from 'ioredis';
import mqtt, { type MqttClient } from 'mqtt';
import { AppConfig } from '../../config/config.service';
import { Point, InfluxService } from '../../infra/influx/influx.service';
import { KafkaService } from '../../infra/kafka/kafka.service';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { REDIS, requireEnv } from '../../infra/redis/redis.module';
import { DeviceContextService } from '../../modules/telemetry/device-context.service';
import { decode, PacketError } from '../../modules/telemetry/packet';
import { REDIS_KEYS, type TelemetryMessage, toMessage } from '../../modules/telemetry/telemetry-message';

const TELEMETRY_TOPIC = 'iccms/telemetry/+';
const BEACON_TOPIC = 'iccms/beacons/+';
const FLUSH_MS = 50;
const FLUSH_MAX = 200;

/**
 * MQTT → Kafka bridge (Section 9.3): subscribes iccms/telemetry/+, decodes and validates, attaches
 * vehicle/trip, produces to `truck-telemetry` keyed by device (per-device ordering). Persistent
 * session (fixed client id, clean=false, QoS 1) so the broker queues packets while the worker restarts.
 */
@Injectable()
export class MqttBridge implements OnApplicationBootstrap, OnApplicationShutdown {
  private readonly logger = new Logger(MqttBridge.name);
  private client?: MqttClient;
  private pending: { key: string; value: TelemetryMessage }[] = [];
  private timer?: NodeJS.Timeout;

  constructor(
    private readonly config: AppConfig,
    private readonly kafka: KafkaService,
    private readonly context: DeviceContextService,
    private readonly influx: InfluxService,
    private readonly prisma: PrismaService,
    @Inject(REDIS) private readonly redis: Redis,
  ) {}

  async onApplicationBootstrap() {
    const url = requireEnv(this.config.get('MQTT_URL'), 'MQTT_URL');
    await this.kafka.warmUp(); // producer ready before the first packet arrives
    this.client =await mqtt.connectAsync(url, {
      clientId: 'iccms-bridge',
      clean: false,
      username: requireEnv(this.config.get('MQTT_BRIDGE_USERNAME'), 'MQTT_BRIDGE_USERNAME'),
      password: requireEnv(this.config.get('MQTT_BRIDGE_PASSWORD'), 'MQTT_BRIDGE_PASSWORD'),
      reconnectPeriod: 2000,
    });
    await this.client.subscribeAsync([TELEMETRY_TOPIC, BEACON_TOPIC], { qos: 1 });
    this.client.on('message', (topic, payload) => void this.onMessage(topic, payload));
    this.client.on('error', (e) => this.logger.error({ msg: 'mqtt error', error: e.message }));
    this.logger.log({ msg: 'mqtt bridge subscribed', url: url.replace(/\/\/.*@/, '//***@') });
  }

  async onApplicationShutdown() {
    if (this.timer) clearTimeout(this.timer);
    await this.flush();
    await this.client?.endAsync().catch(() => undefined);
  }

  async onMessage(topic: string, payload: Buffer) {
    const [, kind, username] = topic.split('/');
    if (kind === 'beacons') return this.onBeacon(username, payload);
    const receivedAt = new Date();
    await this.redis.incr(REDIS_KEYS.counter('received'));
    const device = await this.context.device(username);
    try {
      const reading = decode(payload, device?.deviceCode ?? username.toUpperCase(), receivedAt);
      if (!device) await this.redis.incr(REDIS_KEYS.counter('unknown_device'));
      const tripId = device?.vehicleId ? await this.context.activeTripId(device.vehicleId) : null;
      this.pending.push({ key: reading.deviceCode, value: toMessage(reading, { vehicleId: device?.vehicleId ?? null, tripId }, receivedAt) });
      await this.markSeen(reading.deviceCode, receivedAt);
      if (this.pending.length >= FLUSH_MAX) await this.flush();
      else this.timer ??= setTimeout(() => void this.flush(), FLUSH_MS);
    } catch (e) {
      const reason = e instanceof PacketError ? e.reason : 'ERROR';
      await this.redis.incr(REDIS_KEYS.counter(`dropped:${reason}`));
      this.logger.warn({ msg: 'packet dropped', reason, username, error: (e as Error).message });
    }
  }

  private async flush() {
    this.timer = undefined;
    if (!this.pending.length) return;
    const batch = this.pending;
    this.pending = [];
    try {
      await this.kafka.send('truck-telemetry', batch);
    } catch (e) {
      // Put them back; the next flush retries (kafkajs already retried internally).
      this.pending = batch.concat(this.pending);
      this.logger.error({ msg: 'kafka produce failed, will retry', count: batch.length, error: (e as Error).message });
      this.timer ??= setTimeout(() => void this.flush(), 1000);
    }
  }

  /** lastSeen in Redis for the offline check; the DB column at most once a minute per device. */
  private async markSeen(deviceCode: string, at: Date) {
    await this.redis.hset(REDIS_KEYS.lastSeen, deviceCode, String(at.getTime()));
    if (await this.redis.srem(REDIS_KEYS.offline, deviceCode)) this.logger.log({ msg: 'device back online', deviceCode });
    if (await this.redis.set(`telemetry:lastseen:db:${deviceCode}`, '1', 'EX', 60, 'NX')) {
      await this.prisma.iotDevice.updateMany({ where: { deviceCode }, data: { lastSeenAt: at } }).catch(() => undefined);
    }
  }

  /** SYN-19 pallet movement (simulated BLE beacons) → InfluxDB `beacon`. Low volume, written directly. */
  private async onBeacon(username: string, payload: Buffer) {
    try {
      const b = JSON.parse(payload.toString('utf8')) as { site?: string; beacon?: string; tag?: string; rssi?: number; ts?: string };
      if (!b.site || !b.beacon || !b.tag || typeof b.rssi !== 'number') throw new Error('incomplete beacon');
      const p = new Point('beacon').tag('site_id', b.site).tag('beacon_id', b.beacon).stringField('batch_tag', b.tag).intField('rssi', b.rssi).timestamp(b.ts ? new Date(b.ts) : new Date());
      this.influx.writeApi().writePoint(p);
    } catch (e) {
      await this.redis.incr(REDIS_KEYS.counter('dropped:BEACON'));
      this.logger.warn({ msg: 'beacon dropped', username, error: (e as Error).message });
    }
  }
}
