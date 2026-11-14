/**
 * M9 live test: the three incident paths end to end on the dev stack (docs/TESTING.md, M9).
 *
 * Needs: docker compose dev stack up, migrations + seed applied, `npm run build` done, and both
 *   node --env-file=.env dist/main.js     (API: public offer page)
 *   node --env-file=.env dist/worker.js   (worker, TELEMETRY_TIME_SCALE=60, log to WORKER_LOG)
 * running. Then:
 *   WORKER_LOG=<worker log> API_LOG=<api log> node --env-file=.env -r ts-node/register/transpile-only test/incidents/run.ts
 *
 * Devices publish real MQTT packets (the simulator's binary format); the pipeline raises the alerts and
 * the worker's incident engine decides. Offer tokens are read from the console SMS lines in the
 * worker log (SMS_PROVIDER=console), exactly what a buyer would receive.
 *
 * Scenarios (spec M9 tests):
 *   1. reefer_failure, cold storage reachable → offer to the nearest cold storage → buyer accepts on the
 *      public page → batches DIVERTED + DIVERSION route v2 proposed; reused token → 410; driver silent → managers told
 *   2. reefer_failure, no cold storage → RESCUE_PICKUP by the nearby truck: two route proposals
 *   3. reefer_failure, no cold storage, no rescue → buyer offers: closed / wrong product / low grade excluded,
 *      reject → next buyer, expiry → next, none left → MANUAL + CRITICAL alert; expired token → 410
 *   4. temp_drift_recoverable → DRIVER_FIX → temperature back in range → RESOLVED, no diversion
 *   5. compliance report of a batch matches InfluxDB (independent raw query); traceability CSV has the diversion
 * Prints a JSON report; exit code 1 if any check failed. Leaves the seeded buyers as they were.
 */
import 'reflect-metadata';
import { InfluxDB } from '@influxdata/influxdb-client';
import { Module } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { type Batch, PrismaClient } from '@prisma/client';
import Handlebars from 'handlebars';
import Redis from 'ioredis';
import mqtt, { type MqttClient } from 'mqtt';
import { createHash, randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { encodeBinary } from '../../src/modules/telemetry/packet';

/* eslint-disable @typescript-eslint/no-require-imports, @typescript-eslint/no-explicit-any */
const dist = (p: string) => require(join(__dirname, '..', '..', 'dist', p));

const env = (k: string, d?: string) => {
  const v = process.env[k] ?? d;
  if (v === undefined) throw new Error(`${k} is required`);
  return v;
};
const API = env('API_URL', 'http://127.0.0.1:3000');
const WORKER_LOG = env('WORKER_LOG');
const API_LOG = env('API_LOG');
const SCALE = Number(env('TELEMETRY_TIME_SCALE', '60'));
const SECRET = env('SEED_DEVICE_SECRET', 'dev-device-secret');
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const minutes = (m: number) => (m * 60_000) / SCALE;
const CACHE_WAIT_MS = 31_000; // the bridge caches "active trip of this vehicle" for 30 real seconds

const prisma = new PrismaClient();
const redis = new Redis(env('REDIS_URL'));
const influx = new InfluxDB({ url: env('INFLUX_URL'), token: env('INFLUX_TOKEN') }).getQueryApi(env('INFLUX_ORG'));

type Check = { scenario: string; check: string; pass: boolean; measured: unknown };
const checks: Check[] = [];
const logs: Record<string, unknown> = {};
function check(scenario: string, name: string, pass: boolean, measured: unknown) {
  checks.push({ scenario, check: name, pass, measured });
  console.log(`${pass ? 'PASS' : 'FAIL'} [${scenario}] ${name}: ${JSON.stringify(measured)}`);
}

async function waitFor<T>(what: string, fn: () => Promise<T | null | undefined | false>, timeoutMs: number, everyMs = 250): Promise<T | null> {
  const end = Date.now() + timeoutMs;
  while (Date.now() < end) {
    const v = await fn();
    if (v) return v;
    await sleep(everyMs);
  }
  console.log(`  (timed out waiting for ${what})`);
  return null;
}

async function device(code: string): Promise<MqttClient> {
  return mqtt.connectAsync(env('MQTT_URL'), { username: code.toLowerCase(), password: `${code}:${SECRET}`, clientId: `m9-${code}-${process.pid}`, reconnectPeriod: 0 });
}

let seq = 5_000_000 + (Date.now() % 1_000_000);
function publish(c: MqttClient, code: string, o: { tempC: number; reeferOn: boolean; lat: number; lng: number }) {
  const buf = encodeBinary({ ts: new Date(), seq: seq++, tempC: o.tempC, humidityPct: 90, ax: 0.01, ay: 0.01, az: 0.98, shockG: 0.2, ethylenePpm: 0.1, lat: o.lat, lng: o.lng, reeferOn: o.reeferOn, setpointC: 2, doorOpen: false, batteryPct: 80 });
  return c.publishAsync(`iccms/telemetry/${code.toLowerCase()}`, buf, { qos: 1 });
}

/** One packet per real second (= one config minute) for `seconds`. */
async function stream(c: MqttClient, code: string, seconds: number, o: { tempC: number | ((i: number) => number); reeferOn: boolean; lat: number; lng: number }) {
  for (let i = 0; i < seconds; i++) {
    await publish(c, code, { ...o, tempC: typeof o.tempC === 'function' ? o.tempC(i) : o.tempC });
    await sleep(1000);
  }
}

const FAIL_POS = { lat: 19.87, lng: 75.34 }; // Chh. Sambhajinagar city

/** A trip IN_PROGRESS on the vehicle of `deviceCode` with fresh ROHU batches on board. */
async function seedTrip(deviceCode: string, kgs: number[], grade: 'A' | 'B' | 'C' | null = null) {
  const dev = await prisma.iotDevice.findUniqueOrThrow({ where: { deviceCode }, include: { vehicle: true } });
  const vehicle = dev.vehicle!;
  await prisma.trip.updateMany({ where: { vehicleId: vehicle.id, status: 'IN_PROGRESS' }, data: { status: 'COMPLETED', completedAt: new Date() } });
  const [site, product, operator, driver] = await Promise.all([
    prisma.site.findUniqueOrThrow({ where: { code: 'DCK-PTN' } }),
    prisma.product.findUniqueOrThrow({ where: { code: 'ROHU' } }),
    prisma.user.findFirstOrThrow({ where: { role: 'OPERATOR' } }),
    prisma.user.findFirstOrThrow({ where: { role: 'DRIVER' } }),
  ]);
  const trip = await prisma.trip.create({
    data: { code: `TRP-M9-${deviceCode}-${Date.now()}`, vehicleId: vehicle.id, driverId: driver.id, depotSiteId: site.id, status: 'IN_PROGRESS', plannedStart: new Date(), startedAt: new Date(), distanceKm: 40 },
  });
  const batches: Batch[] = [];
  for (const kg of kgs) {
    const b = await prisma.batch.create({
      data: {
        id: randomUUID(), code: `M9-${Date.now()}-${batches.length}`, productId: product.id, sourceType: 'FISHERY', sourceSiteId: site.id, currentSiteId: site.id,
        caughtOrHarvestedAt: new Date(Date.now() - 6 * 3_600_000), weightKg: kg, vesselId: 'MH-M9', iceToFishRatio: 1, initialCoreTemp: 2, currentGrade: grade,
        status: 'IN_TRANSIT', createdBy: operator.id, deviceId: 'm9-e2e', capturedAt: new Date(), recordHash: '0'.repeat(64),
      },
    });
    await prisma.tripBatch.create({ data: { tripId: trip.id, batchId: b.id, loadedBy: operator.id, loadedAt: new Date() } });
    batches.push(b);
  }
  await redis.del(`telemetry:breach:${deviceCode}`);
  return { trip, batches, vehicle };
}

async function incidentOf(tripId: string) {
  return prisma.incident.findFirst({ where: { tripId }, orderBy: { createdAt: 'desc' }, include: { offers: { include: { buyer: true }, orderBy: { createdAt: 'asc' } } } });
}
const steps = (inc: { decisionLog: unknown } | null) => ((inc?.decisionLog ?? []) as { step: string }[]).map((e) => e.step);

/**
 * Offer token from the console SMS to `phone`. Offers are sent by the worker (engine, timeouts) or by
 * the API (the next offer after a buyer rejects on the public page), so both logs are read; a token
 * only counts if its SHA-256 belongs to an offer created since `since` (not one from an earlier run).
 */
async function tokenFor(phone: string, since: Date): Promise<string | null> {
  return waitFor(`SMS to ${phone}`, async () => {
    const lines = [WORKER_LOG, API_LOG].flatMap((f) => readFileSync(f, 'utf8').split(/\r?\n/));
    for (const l of lines.reverse()) {
      if (!l.includes(`to=${phone}`)) continue;
      const m = /\/offer\/([A-Za-z0-9_-]{43})/.exec(l);
      if (!m) continue;
      const hash = createHash('sha256').update(m[1], 'utf8').digest('hex');
      if (await prisma.diversionOffer.findFirst({ where: { tokenHash: hash, createdAt: { gte: since } } })) return m[1];
    }
    return null;
  }, 15_000);
}
const logLines = () => new Date();

async function http(method: 'GET' | 'POST', path: string) {
  const res = await fetch(`${API}${path}`, { method });
  return { status: res.status, body: await res.text() };
}

// ───────────────────────────────────────────── scenarios

async function scenario1(dev1: MqttClient) {
  const S = '1 reefer_failure → cold storage';
  const { trip, batches } = await seedTrip('DEV-001', [120, 80]);
  const waluj = await prisma.backupBuyer.findFirstOrThrow({ where: { name: { startsWith: 'Waluj Cold Storage' } } });
  const mark = logLines();
  await stream(dev1, 'DEV-001', 18, { tempC: 8.5, reeferOn: false, ...FAIL_POS });
  const inc = await waitFor('incident', async () => {
    const i = await incidentOf(trip.id);
    return i?.offers.length ? i : null;
  }, 20_000);
  check(S, 'classified REEFER_FAILURE, offer to the nearest cold storage', inc?.kind === 'REEFER_FAILURE' && inc.offers[0]?.buyerId === waluj.id && inc.decidedAction === 'DIVERT_COLD_STORAGE', {
    kind: inc?.kind, action: inc?.decidedAction, offeredTo: inc?.offers[0]?.buyer.name, steps: steps(inc),
  });
  const token = await tokenFor(waluj.phone, mark);
  check(S, 'buyer received the SMS link', !!token, { phone: waluj.phone, tokenLength: token?.length ?? null });
  if (!inc || !token) return;
  const page = await http('GET', `/offer/${token}`);
  check(S, 'public offer page opens', page.status === 200 && page.body.includes('Accept') && page.body.includes(waluj.name), { status: page.status });
  const t0 = Date.now();
  const accept = await http('POST', `/offer/${token}/accept`);
  check(S, 'accept on the public page', accept.status === 200 && accept.body.includes('Offer accepted'), { status: accept.status });
  const reuse = await http('POST', `/offer/${token}/accept`);
  check(S, 'reused token → 410', reuse.status === 410, { status: reuse.status });

  const plan = await waitFor('route v2', () => prisma.routePlan.findFirst({ where: { tripId: trip.id, status: 'PROPOSED' } }), 15_000);
  const stops = plan ? await prisma.tripStop.findMany({ where: { tripId: trip.id, routeVersion: plan.version }, orderBy: { seq: 'asc' } }) : [];
  check(S, 'route proposed with the cold-storage stop first (after acceptance only)', !!plan && plan.reason === 'DIVERSION' && stops[0]?.type === 'COLD_STORAGE_DROP' && stops[0]?.buyerId === waluj.id, {
    version: plan?.version, reason: plan?.reason, firstStop: stops[0]?.type, msFromAccept: plan ? plan.createdAt.getTime() - t0 : null,
  });
  const diverted = await prisma.batch.findMany({ where: { id: { in: batches.map((b) => b.id) } }, select: { status: true } });
  const trace = await prisma.traceEvent.count({ where: { batchId: { in: batches.map((b) => b.id) }, eventType: 'DIVERTED' } });
  check(S, 'batches DIVERTED with hash-chained DIVERTED events', diverted.every((b) => b.status === 'DIVERTED') && trace === 2, { statuses: diverted.map((b) => b.status), traceEvents: trace });
  const silent = await waitFor('route-response escalation', async () => readFileSync(WORKER_LOG, 'utf8').split(/\r?\n/).find((l) => l.includes('is still waiting for the driver') && l.includes(trip.code)), minutes(5) + 10_000);
  check(S, 'driver did not answer within ackMinutes → managers texted', !!silent, { found: !!silent });
  const final = await incidentOf(trip.id);
  check(S, 'decision log complete', ['CLASSIFIED', 'COLD_STORAGE_SEARCH', 'OFFER_SENT', 'OFFER_ACCEPTED', 'ROUTE_PROPOSED'].every((s) => steps(final).includes(s)), steps(final));
  logs[S] = final?.decisionLog;
  return { tripId: trip.id, batchIds: batches.map((b) => b.id) };
}

async function scenario2(dev1: MqttClient, dev2: MqttClient) {
  const S = '2 reefer_failure → rescue';
  await prisma.backupBuyer.updateMany({ where: { type: 'COLD_STORAGE' }, data: { active: false } });
  const failing = await seedTrip('DEV-001', [150]);
  const rescue = await seedTrip('DEV-002', [300]);
  await sleep(CACHE_WAIT_MS);
  // The rescue truck reports its position (in range, ~4 km away).
  const healthy = stream(dev2, 'DEV-002', 22, { tempC: 2.5, reeferOn: true, lat: 19.9, lng: 75.36 });
  await sleep(2000);
  await stream(dev1, 'DEV-001', 18, { tempC: 9, reeferOn: false, ...FAIL_POS });
  await healthy;
  const inc = await waitFor('rescue decision', async () => {
    const i = await incidentOf(failing.trip.id);
    return i?.decidedAction ? i : null;
  }, 20_000);
  check(S, 'cold storages unavailable → RESCUE_PICKUP by the nearby truck', inc?.decidedAction === 'RESCUE_PICKUP' && inc.rescueTripId === rescue.trip.id, { action: inc?.decidedAction, rescueTripId: inc?.rescueTripId, steps: steps(inc) });
  const plans = await prisma.routePlan.findMany({ where: { tripId: { in: [failing.trip.id, rescue.trip.id] }, status: 'PROPOSED' } });
  const firstStop = async (tripId: string) => {
    const p = plans.find((x) => x.tripId === tripId);
    return p ? (await prisma.tripStop.findFirst({ where: { tripId, routeVersion: p.version }, orderBy: { seq: 'asc' } }))?.type : null;
  };
  const [a, b] = [await firstStop(failing.trip.id), await firstStop(rescue.trip.id)];
  check(S, 'two-trip replan: handover drop on the failing truck, pickup first on the rescue truck', a === 'RESCUE_DROP' && b === 'RESCUE_PICKUP', { failingFirst: a, rescueFirst: b });
  logs[S] = inc?.decisionLog;
  await prisma.trip.update({ where: { id: rescue.trip.id }, data: { status: 'COMPLETED', completedAt: new Date() } });
}

async function scenario3(dev1: MqttClient) {
  const S = '3 reefer_failure → buyers → MANUAL';
  // Cold storages still inactive; no other truck on the road. Test buyers make the exclusions deterministic
  // (the seeded buyers' hours depend on the time of day the test runs).
  const rohu = (await prisma.product.findUniqueOrThrow({ where: { code: 'ROHU' } })).id;
  const tomato = (await prisma.product.findUniqueOrThrow({ where: { code: 'TOMATO' } })).id;
  const allDay = Object.fromEntries(['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'].map((d) => [d, [['00:00', '23:59']]]));
  const mk = (name: string, o: Record<string, unknown>) =>
    prisma.backupBuyer.create({ data: { name: `E2E ${name} ${Date.now()}`, type: 'LOCAL_MARKET', phone: '+919999900399', lat: 19.88, lng: 75.35, acceptedProductIds: [rohu], minGrade: 'C', discountPct: 50, openingHours: allDay, active: true, ...o } as never });
  const extra = await mk('fallback buyer', {});
  const excludedOnes = [await mk('closed', { openingHours: {}, discountPct: 1 }), await mk('tomato only', { acceptedProductIds: [tomato], discountPct: 1 }), await mk('grade A only', { minGrade: 'A', discountPct: 1 })];
  const cidco = await prisma.backupBuyer.findFirstOrThrow({ where: { name: 'CIDCO Discount Mart' } });
  const { trip } = await seedTrip('DEV-001', [100], 'B');
  await sleep(CACHE_WAIT_MS);
  const mark = logLines();
  await stream(dev1, 'DEV-001', 18, { tempC: 9, reeferOn: false, ...FAIL_POS });
  const first = await waitFor('first offer', async () => (await incidentOf(trip.id))?.offers[0], 20_000);
  const inc1 = await incidentOf(trip.id);
  const search = ((inc1?.decisionLog ?? []) as { step: string; candidates?: { excluded?: { name: string; reason: string }[] } }[]).find((e) => e.step === 'BUYER_SEARCH');
  const reasons = Object.fromEntries((search?.candidates?.excluded ?? []).map((x) => [x.name, x.reason]));
  check(S, 'closed / wrong product / grade too low are excluded with the reason', reasons[excludedOnes[0].name] === 'CLOSED_AT_ETA' && reasons[excludedOnes[1].name] === 'PRODUCT_NOT_ACCEPTED' && reasons[excludedOnes[2].name] === 'GRADE_TOO_LOW', reasons);
  check(S, 'first offer goes to the cheapest eligible buyer (CIDCO, 20 %)', first?.buyerId === cidco.id, { offeredTo: first?.buyer.name });
  const t1 = await tokenFor(cidco.phone, mark);
  const reject = t1 ? await http('POST', `/offer/${t1}/reject`) : null;
  check(S, 'CIDCO rejects on the public page', reject?.status === 200 && !!reject.body.includes('Offer rejected'), { status: reject?.status });
  const again = t1 ? await http('POST', `/offer/${t1}/accept`) : null;
  check(S, 'answering the same token again → 410', again?.status === 410, { status: again?.status });
  const second = await waitFor('second offer', async () => (await incidentOf(trip.id))?.offers[1], 10_000);
  check(S, 'reject → next buyer', !!second && second.buyerId !== cidco.id, { offeredTo: second?.buyer.name });
  // Remaining offers expire (offerMinutes, scaled) one after the other → no buyer left → MANUAL.
  const manual = await waitFor('MANUAL', async () => {
    const i = await incidentOf(trip.id);
    return i?.decidedAction === 'MANUAL' ? i : null;
  }, 4 * minutes(10) + 20_000);
  const statuses = manual?.offers.map((o) => o.status) ?? [];
  check(S, 'offer expiry → next candidate; none left → MANUAL', !!manual && statuses[0] === 'REJECTED' && statuses.length >= 2 && statuses.slice(1).every((x) => x === 'EXPIRED') && manual.offers.some((o) => o.buyerId === extra.id), {
    offers: manual?.offers.map((o) => `${o.buyer.name}:${o.status}`), steps: steps(manual),
  });
  const alert = await prisma.alert.findFirst({ where: { tripId: trip.id, type: 'SPOILAGE_RISK', severity: 'CRITICAL' } });
  check(S, 'managers alerted (CRITICAL, with SMS)', !!alert && [WORKER_LOG, API_LOG].some((f) => readFileSync(f, 'utf8').includes(`Manual action needed on trip ${trip.code}`)), { alert: alert?.message });
  const t2 = await tokenFor(extra.phone, mark);
  const expired = t2 ? await http('GET', `/offer/${t2}`) : null;
  check(S, 'expired token → 410', expired?.status === 410, { status: expired?.status });
  logs[S] = manual?.decisionLog;
  await prisma.backupBuyer.updateMany({ where: { id: { in: [extra.id, ...excludedOnes.map((b) => b.id)] } }, data: { active: false } });
}

async function scenario4(dev1: MqttClient) {
  const S = '4 temp_drift_recoverable';
  const { trip, batches } = await seedTrip('DEV-001', [90]);
  await sleep(CACHE_WAIT_MS);
  await stream(dev1, 'DEV-001', 18, { tempC: 4.6, reeferOn: true, ...FAIL_POS });
  const inc = await waitFor('DRIVER_FIX', async () => {
    const i = await incidentOf(trip.id);
    return i?.decidedAction === 'DRIVER_FIX' ? i : null;
  }, 20_000);
  const fixAlert = await prisma.alert.findFirst({ where: { tripId: trip.id, type: 'DRIVER_FIX' } });
  check(S, 'reefer ON + slow drift → TEMP_DRIFT → DRIVER_FIX instruction to the driver', inc?.kind === 'TEMP_DRIFT' && !!fixAlert, { kind: inc?.kind, action: inc?.decidedAction, alert: fixAlert?.message });
  // The driver closes the door: back in range before the re-check (15 config min).
  await stream(dev1, 'DEV-001', Math.ceil(minutes(15) / 1000) + 3, { tempC: 3.0, reeferOn: true, ...FAIL_POS });
  const done = await waitFor('RESOLVED', async () => {
    const i = await incidentOf(trip.id);
    return i?.status === 'RESOLVED' ? i : null;
  }, 15_000);
  check(S, 'recovered at the re-check → RESOLVED without diversion', !!done && done.offers.length === 0 && steps(done).includes('DRIVER_FIX_RECOVERED'), { status: done?.status, offers: done?.offers.length, steps: steps(done) });
  logs[S] = done?.decisionLog;
  return { tripId: trip.id, batchId: batches[0].id };
}

async function reports(drift: { tripId: string; batchId: string }, divert: { batchIds: string[] } | undefined) {
  const S = '5 reports';
  const { ConfigModule } = dist('config/config.module');
  const { PrismaModule } = dist('infra/prisma/prisma.module');
  const { InfluxModule } = dist('infra/influx/influx.module');
  const { RedisModule } = dist('infra/redis/redis.module');
  const { RealtimeEmitterModule } = dist('modules/realtime/realtime.module');
  const { TelemetryModule } = dist('modules/telemetry/telemetry.module');
  const { TraceModule } = dist('modules/trace/trace.module');
  const { RemoteConfigCoreModule } = dist('modules/remote-config/remote-config.module');
  const { ReportsService } = dist('modules/reports/reports.service');
  @Module({ imports: [ConfigModule, PrismaModule, InfluxModule, RedisModule, RealtimeEmitterModule, TelemetryModule, TraceModule, RemoteConfigCoreModule], providers: [ReportsService] })
  class ReportsE2eModule {}
  const app = await NestFactory.createApplicationContext(ReportsE2eModule, { logger: false });
  try {
    const svc = app.get(ReportsService) as any;
    await sleep(2000); // last points flushed
    const r = await svc.compliance(drift.batchId);
    // Independent check: raw readings of this trip from InfluxDB, averaged per minute here.
    const leg = r.trips[0];
    const raw = await influx.collectRows<{ _time: string; _value: number }>(`from(bucket: "${env('INFLUX_BUCKET')}")
  |> range(start: ${leg.from}, stop: ${leg.to})
  |> filter(fn: (r) => r._measurement == "reefer" and r._field == "temp_c" and r.trip_id == "${drift.tripId}")`);
    const perMin = new Map<string, number[]>();
    for (const p of raw) {
      // aggregateWindow labels each window with its stop time.
      const stop = new Date(Math.floor(Date.parse(p._time) / 60_000) * 60_000 + 60_000);
      const k = (stop > new Date(leg.to) ? new Date(leg.to) : stop).toISOString();
      perMin.set(k, [...(perMin.get(k) ?? []), p._value]);
    }
    const mine = [...perMin.entries()].map(([at, v]) => ({ at, mean: v.reduce((a, b) => a + b, 0) / v.length })).sort((a, b) => a.at.localeCompare(b.at));
    const theirs = (r.log as { at: string; tempC: number }[]).map((x) => ({ at: new Date(x.at).toISOString(), mean: x.tempC }));
    const same = mine.length === theirs.length && mine.every((m, i) => m.at === theirs[i].at && Math.abs(m.mean - theirs[i].mean) <= 0.01);
    check(S, 'compliance log = InfluxDB raw readings averaged per minute', same && raw.length > 0, { rawPoints: raw.length, minutes: theirs.length, report: theirs, independent: mine.map((m) => ({ at: m.at, mean: Math.round(m.mean * 100) / 100 })) });
    const minRaw = Math.min(...raw.map((p) => p._value));
    const maxRaw = Math.max(...raw.map((p) => p._value));
    const outMinutes = mine.filter((m) => m.mean > 4 || m.mean < 0).length;
    const reportOut = (r.summary.excursions as { minutes: number }[]).reduce((a, e) => a + e.minutes, 0);
    check(S, 'excursion minutes and min/max agree with the raw data', reportOut === outMinutes && r.summary.minC >= minRaw - 1e-9 && r.summary.maxC <= maxRaw + 1e-9, { summary: r.summary, rawMin: minRaw, rawMax: maxRaw, outOfRangeMinutes: outMinutes });
    const html = Handlebars.compile(readFileSync(join(__dirname, '..', '..', 'views', 'compliance.hbs'), 'utf8'))(svc.complianceView(r));
    const csv = svc.complianceCsv(r) as string;
    check(S, 'HTML and CSV render', html.includes(r.batch.code) && csv.split('\r\n').length - 2 === theirs.length, { htmlBytes: html.length, csvRows: csv.split('\r\n').length - 2 });
    if (divert) {
      const now = new Date();
      const t = (await svc.traceability(new Date(now.getTime() - 3_600_000).toISOString(), now.toISOString())) as string;
      const codes = await prisma.batch.findMany({ where: { id: { in: divert.batchIds } }, select: { code: true } });
      check(S, 'traceability CSV lists the DIVERTED shipping events', codes.every((c) => t.split('\r\n').some((l) => l.includes(c.code) && l.includes(',SHIPPING,DIVERTED,'))), { rows: t.split('\r\n').length - 2 });
    }
  } finally {
    await app.close();
  }
}

async function main() {
  const coldBefore = await prisma.backupBuyer.findMany({ where: { type: 'COLD_STORAGE' }, select: { id: true, active: true } });
  const [dev1, dev2] = await Promise.all([device('DEV-001'), device('DEV-002')]);
  try {
    const divert = await scenario1(dev1);
    await sleep(CACHE_WAIT_MS);
    await scenario2(dev1, dev2);
    await scenario3(dev1);
    const drift = await scenario4(dev1);
    await reports(drift, divert);
  } finally {
    for (const c of coldBefore) await prisma.backupBuyer.update({ where: { id: c.id }, data: { active: c.active } });
    await prisma.trip.updateMany({ where: { code: { startsWith: 'TRP-M9-' }, status: 'IN_PROGRESS' }, data: { status: 'COMPLETED', completedAt: new Date() } });
    await Promise.all([dev1.endAsync(), dev2.endAsync()]);
  }
  const passed = checks.every((c) => c.pass);
  console.log(JSON.stringify({ scale: SCALE, passed, checks, decisionLogs: logs }, null, 2));
  process.exitCode = passed ? 0 : 1;
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
