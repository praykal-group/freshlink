/**
 * M8 pipeline test against the real dev stack (docs/TESTING.md, Section 16 "Pipeline").
 *
 * Needs: docker compose dev stack up (MOSQ_DEVICE_COUNT=500 for the load step), migrations + seed
 * applied, and the WORKER running with TELEMETRY_TIME_SCALE=60 (1 config minute = 1 real second):
 *   npm run start:worker   (with .env pointing at the stack)
 * Then:
 *   npx ts-node --transpile-only test/pipeline/run.ts [--skip-load]
 *
 * Steps and targets:
 *   1. sensor → InfluxDB p95 ≤ 500 ms over 1,000 packets (SRV-02), ms-accurate legs, after warm-up
 *   2. breach → shelf-life estimate stored ≤ 5 s (SYN-04)
 *   3. alert after the (scaled) 15-min persistence window, exactly one per breach (SYN-07)
 *   4. escalation after the (scaled) 5-min ack timeout (DA-FR-07)
 *   5. binary packet with a bad CRC is dropped and counted
 *   6. 500 devices at a 60 s (scaled → 1 s) interval: zero loss (seq gaps) in InfluxDB
 *   7. tiering export file created (TIERING_LOCAL_DIR)
 * Prints a JSON report; exit code 1 if any target failed.
 */
import { InfluxDB } from '@influxdata/influxdb-client';
import { PrismaClient } from '@prisma/client';
import { Queue } from 'bullmq';
import { Kafka, logLevel } from 'kafkajs';
import Redis from 'ioredis';
import mqtt, { type MqttClient } from 'mqtt';
import { randomUUID } from 'node:crypto';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { bullConnection } from '../../src/infra/queue/queues';
import { encodeBinary } from '../../src/modules/telemetry/packet';
import { archiveKey, dayToArchive } from '../../src/workers/jobs/tiering';

const env = (k: string, d?: string) => {
  const v = process.env[k] ?? d;
  if (v === undefined) throw new Error(`${k} is required`);
  return v;
};
const MQTT_URL = env('MQTT_URL', 'mqtt://127.0.0.1:1883');
const SECRET = env('SEED_DEVICE_SECRET', 'dev-device-secret');
const SCALE = Number(env('TELEMETRY_TIME_SCALE', '60'));
const SKIP_LOAD = process.argv.includes('--skip-load');
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const minutes = (m: number) => (m * 60_000) / SCALE;

const prisma = new PrismaClient();
const redis = new Redis(env('REDIS_URL', 'redis://127.0.0.1:6379'));
const influx = new InfluxDB({ url: env('INFLUX_URL', 'http://127.0.0.1:8086'), token: env('INFLUX_TOKEN', 'dev-influx-token') }).getQueryApi(env('INFLUX_ORG', 'iccms'));
const BUCKET = env('INFLUX_BUCKET', 'telemetry');

type Result = { step: string; target: string; measured: unknown; pass: boolean };
const results: Result[] = [];
const record = (step: string, target: string, measured: unknown, pass: boolean) => {
  results.push({ step, target, measured, pass });
  console.log(`${pass ? 'PASS' : 'FAIL'} ${step}: ${JSON.stringify(measured)} (target ${target})`);
};

async function device(n: number): Promise<MqttClient> {
  const code = `DEV-${String(n).padStart(3, '0')}`;
  return mqtt.connectAsync(MQTT_URL, { username: code.toLowerCase(), password: `${code}:${SECRET}`, clientId: `pipeline-${code}-${process.pid}`, reconnectPeriod: 0 });
}

const packet = (n: number, seq: number, tempC: number, ts = new Date()) =>
  encodeBinary({ ts, seq, tempC, humidityPct: 90, ax: 0.01, ay: 0.01, az: 0.98, shockG: 0.2, ethylenePpm: 0.2, lat: 19.87, lng: 75.34, reeferOn: true, setpointC: 2, doorOpen: false, batteryPct: 80 });

const p95 = (xs: number[]) => {
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.min(s.length - 1, Math.floor(0.95 * s.length))];
};

/** A trip IN_PROGRESS on the vehicle carrying DEV-001, with one fish batch on board (0–4 °C). */
async function seedTrip() {
  const dev = await prisma.iotDevice.findUniqueOrThrow({ where: { deviceCode: 'DEV-001' }, include: { vehicle: true } });
  if (!dev.vehicle) throw new Error('DEV-001 is not attached to a vehicle (run the seed)');
  await prisma.trip.updateMany({ where: { vehicleId: dev.vehicle.id, status: 'IN_PROGRESS' }, data: { status: 'COMPLETED', completedAt: new Date() } });
  const [site, product, operator, driver] = await Promise.all([
    prisma.site.findUniqueOrThrow({ where: { code: 'DCK-PTN' } }),
    prisma.product.findUniqueOrThrow({ where: { code: 'ROHU' } }),
    prisma.user.findFirstOrThrow({ where: { role: 'OPERATOR' } }),
    prisma.user.findFirstOrThrow({ where: { role: 'DRIVER' } }),
  ]);
  const batch = await prisma.batch.create({
    data: {
      id: randomUUID(), code: `PIPE-${Date.now()}`, productId: product.id, sourceType: 'FISHERY', sourceSiteId: site.id, currentSiteId: site.id,
      caughtOrHarvestedAt: new Date(Date.now() - 6 * 3_600_000), weightKg: 120, vesselId: 'MH-PIPE', iceToFishRatio: 1, initialCoreTemp: 2,
      status: 'IN_TRANSIT', createdBy: operator.id, deviceId: 'pipeline', capturedAt: new Date(), recordHash: '0'.repeat(64),
    },
  });
  const trip = await prisma.trip.create({
    data: { code: `TRP-PIPE-${Date.now()}`, vehicleId: dev.vehicle.id, driverId: driver.id, depotSiteId: site.id, status: 'IN_PROGRESS', plannedStart: new Date(), startedAt: new Date(), distanceKm: 50 },
  });
  await prisma.tripBatch.create({ data: { tripId: trip.id, batchId: batch.id, loadedBy: operator.id, loadedAt: new Date() } });
  await redis.del('telemetry:breach:DEV-001');
  return { trip, batch };
}

async function main() {
  // ── 1. latency over 1,000 packets (devices 1–50, 20 packets each) ──
  // Packet time is whole seconds (u32 epoch_s), so "now − packet ts" carries 0–999 ms of rounding
  // and cannot resolve a 500 ms target. Measured instead, millisecond-accurate, in two legs:
  //   publish → bridge receipt: this script's publish time vs `receivedAt` (read from Kafka here)
  //   bridge → Influx written:  the writer's metrics:latency:bridge_to_influx_ms samples
  // and the target is checked on p95(leg 1) + p95(leg 2), an upper bound on the end-to-end p95.
  const probe = new Kafka({ clientId: 'pipeline-probe', brokers: env('KAFKA_BROKERS', '127.0.0.1:29092').split(','), logLevel: logLevel.NOTHING })
    .consumer({ groupId: `pipeline-probe-${Date.now()}`, maxWaitTimeInMs: 50 });
  const publishedAt = new Map<string, number>();
  const toBridge: number[] = [];
  let joined = false;
  probe.on(probe.events.GROUP_JOIN, () => (joined = true));
  await probe.connect();
  await probe.subscribe({ topic: 'truck-telemetry', fromBeginning: false });
  await probe.run({
    eachMessage: async ({ message }) => {
      const m = JSON.parse(message.value?.toString() ?? '{}');
      const t0 = publishedAt.get(`${m.deviceCode}:${m.seq}`);
      if (t0 !== undefined) toBridge.push(Date.parse(m.receivedAt) - t0);
    },
  });
  while (!joined) await sleep(100);

  const clients = await Promise.all(Array.from({ length: 50 }, (_, i) => device(i + 1)));
  let seq = 1_000_000 + (Date.now() % 1_000_000);
  const round = () =>
    Promise.all(clients.map((c, i) => {
      const code = `DEV-${String(i + 1).padStart(3, '0')}`;
      const s = seq++;
      publishedAt.set(`${code}:${s}`, Date.now());
      return c.publishAsync(`iccms/telemetry/${code.toLowerCase()}`, packet(i + 1, s, 2.5), { qos: 1 });
    }));
  // Warm-up (excluded): the first packet per device fills the worker's device/trip caches. Real
  // devices report every 60 s around the clock, so SRV-02 is a steady-state target.
  await round();
  await sleep(2000);
  toBridge.length = 0;
  await redis.del('metrics:latency:sensor_to_influx_ms', 'metrics:latency:bridge_to_influx_ms');
  for (let r = 0; r < 20; r++) {
    await round();
    await sleep(100);
  }
  await sleep(3000);
  await probe.disconnect();
  const bridgeToInflux = (await redis.lrange('metrics:latency:bridge_to_influx_ms', 0, -1)).map(Number);
  const sensorTs = (await redis.lrange('metrics:latency:sensor_to_influx_ms', 0, -1)).map(Number);
  const bound = p95(toBridge) + p95(bridgeToInflux);
  record(
    'sensor→Influx p95 (1,000 packets, after 50-packet warm-up)',
    '≤ 500 ms',
    {
      publishToBridge: { samples: toBridge.length, p95Ms: p95(toBridge) },
      bridgeToInflux: { samples: bridgeToInflux.length, p95Ms: p95(bridgeToInflux) },
      endToEndP95UpperBoundMs: bound,
      packetTsMetricP95Ms_1sResolution: p95(sensorTs),
    },
    toBridge.length >= 950 && bridgeToInflux.length >= 950 && bound <= 500,
  );
  await Promise.all(clients.slice(1).map((c) => c.endAsync()));
  const dev1 = clients[0];

  // ── 2–4. breach → shelf life, persistence alert, escalation ──
  const { trip, batch } = await seedTrip();
  // Step 1 made the bridge cache "no trip" for DEV-001's truck; that cache lives 30 real seconds (not time-scaled).
  await sleep(31_000);
  const breachAt = new Date();
  let s = 1;
  const sendTemp = (t: number) => dev1.publishAsync('iccms/telemetry/dev-001', packet(1, s++, t), { qos: 1 });
  await sendTemp(3); // in range
  await sendTemp(8); // breach starts
  const shelfDeadline = Date.now() + 5000;
  let shelf = null;
  while (Date.now() < shelfDeadline && !shelf) {
    shelf = await prisma.shelfLifeEstimate.findFirst({ where: { batchId: batch.id, trigger: 'BREACH', createdAt: { gte: breachAt } } });
    if (!shelf) await sleep(100);
  }
  record('breach → shelf-life stored', '≤ 5 s', { ms: shelf ? shelf.createdAt.getTime() - breachAt.getTime() : null }, !!shelf && shelf.createdAt.getTime() - breachAt.getTime() <= 5000);

  const persistEnd = Date.now() + minutes(15) + 4000;
  while (Date.now() < persistEnd) {
    await sendTemp(8.5);
    await sleep(minutes(1));
  }
  const alerts = await prisma.alert.findMany({ where: { tripId: trip.id, type: 'TEMP_EXCURSION' } });
  record('alert after persistence window, no duplicates', 'exactly 1 TEMP_EXCURSION', { alerts: alerts.length }, alerts.length === 1);

  if (alerts[0]) {
    await sleep(minutes(5) + 3000);
    const a = await prisma.alert.findUnique({ where: { id: alerts[0].id } });
    record('escalation after ack timeout', 'status ESCALATED', { status: a?.status }, a?.status === 'ESCALATED');
  }

  // ── 5. bad CRC dropped ──
  const before = Number((await redis.get('metrics:telemetry:dropped:BAD_CRC')) ?? 0);
  const bad = packet(1, s++, 3);
  bad[8] ^= 0xff;
  await dev1.publishAsync('iccms/telemetry/dev-001', bad, { qos: 1 });
  await sleep(1500);
  const after = Number((await redis.get('metrics:telemetry:dropped:BAD_CRC')) ?? 0);
  record('binary packet with bad CRC dropped', 'counter +1', { before, after }, after === before + 1);
  await dev1.endAsync();

  // ── 6. 500 devices, zero loss ──
  if (!SKIP_LOAD) {
    const N = 500;
    const ROUNDS = 10;
    const runId = Date.now() % 100_000_000; // seq base unique to this run
    const start = new Date();
    const fleet: MqttClient[] = [];
    for (let i = 1; i <= N; i += 50) fleet.push(...(await Promise.all(Array.from({ length: Math.min(50, N - i + 1) }, (_, k) => device(i + k)))));
    for (let r = 0; r < ROUNDS; r++) {
      await Promise.all(fleet.map((c, i) => c.publishAsync(`iccms/telemetry/dev-${String(i + 1).padStart(3, '0')}`, packet(i + 1, runId + r, 2 + (i % 3)), { qos: 1 })));
      await sleep(minutes(1)); // 60 s interval, scaled
    }
    await Promise.all(fleet.map((c) => c.endAsync()));
    await sleep(5000);
    const rows = await influx.collectRows<{ _value: number }>(`from(bucket: "${BUCKET}")
  |> range(start: ${start.toISOString()})
  |> filter(fn: (r) => r._measurement == "reefer" and r._field == "seq" and r._value >= ${runId} and r._value < ${runId + ROUNDS})
  |> group() |> count()`);
    const stored = rows[0]?._value ?? 0;
    record('500 devices × 10 packets, zero loss', `${N * ROUNDS} points`, { sent: N * ROUNDS, stored }, stored === N * ROUNDS);
  }

  // ── 7. tiering export file ──
  const dir = process.env.TIERING_LOCAL_DIR;
  if (dir) {
    const q = new Queue('maintenance', { connection: bullConnection(env('REDIS_URL', 'redis://127.0.0.1:6379')) });
    await q.add('telemetry-tiering', {}, { jobId: `pipeline-tiering-${Date.now()}` });
    await q.close();
    const file = join(dir, archiveKey(dayToArchive(new Date())));
    const deadline = Date.now() + 15_000;
    while (!existsSync(file) && Date.now() < deadline) await sleep(500);
    record('tiering export file created', file, { exists: existsSync(file) }, existsSync(file));
  }

  console.log(JSON.stringify({ scale: SCALE, results, passed: results.every((r) => r.pass) }, null, 2));
  process.exitCode = results.every((r) => r.pass) ? 0 : 1;
}

main()
  .catch((e) => {
    console.error(e);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
    redis.disconnect();
  });
