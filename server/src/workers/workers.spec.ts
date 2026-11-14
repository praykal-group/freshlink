import { gunzipSync } from 'node:zlib';
import { ThresholdProcessor } from './consumers/threshold-processor';
import { archiveKey, dayToArchive, rowsToCsv, TieringJob } from './jobs/tiering';
import { MaintenanceWorker } from './jobs/maintenance.worker';

const TRIP = '9a8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a7b';

/** Minimal Redis double with the commands the workers use. */
function fakeRedis() {
  const kv = new Map<string, string>();
  const hashes = new Map<string, Map<string, string>>();
  const sets = new Map<string, Set<string>>();
  const lists = new Map<string, string[]>();
  return {
    kv, hashes, sets, lists,
    get: async (k: string) => kv.get(k) ?? null,
    set: async (k: string, v: string) => (kv.set(k, v), 'OK'),
    hget: async (k: string, f: string) => hashes.get(k)?.get(f) ?? null,
    hset: async (k: string, f: string, v: string) => (hashes.set(k, (hashes.get(k) ?? new Map()).set(f, v)), 1),
    sadd: async (k: string, v: string) => {
      const s = sets.get(k) ?? new Set();
      const added = s.has(v) ? 0 : 1;
      sets.set(k, s.add(v));
      return added;
    },
    lpush: async (k: string, v: string) => lists.set(k, [v, ...(lists.get(k) ?? [])]).size,
    ltrim: async () => 'OK',
  };
}

describe('ThresholdProcessor.process', () => {
  const cargo = {
    tripId: TRIP, code: 'TRP-1', vehicleId: 'veh-1', driverId: 'drv-1',
    limits: { tempMin: 0, tempMax: 4, humidityMin: 85, humidityMax: 98, shockMaxG: 3, ethyleneMaxPpm: null, ethyleneSensitiveOnBoard: false },
    batches: [{ batchId: 'b1', safeTempMax: 4, shockMaxG: 3 }, { batchId: 'b2', safeTempMax: 4, shockMaxG: 3 }],
  };
  function setup() {
    const redis = fakeRedis();
    const alerts = { raise: jest.fn().mockResolvedValue({ id: 'a1' }) };
    const shelfLife = { recompute: jest.fn().mockResolvedValue({}) };
    const trace = { append: jest.fn() };
    const realtime = { toTrip: jest.fn() };
    const prisma = { $transaction: jest.fn(async (fn: (tx: unknown) => unknown) => fn({})) };
    const context = { tripCargo: jest.fn().mockResolvedValue(cargo) };
    const p = new ThresholdProcessor({} as never, context as never, alerts as never, shelfLife as never, trace as never, {} as never, realtime as never, prisma as never, redis as never);
    return { p, redis, alerts, shelfLife, trace, realtime };
  }
  const msg = (min: number, tempC: number) => ({
    deviceCode: 'DEV-001', vehicleId: 'veh-1', tripId: TRIP, ts: new Date(Date.UTC(2026, 10, 14, 5, min)).toISOString(), receivedAt: new Date().toISOString(),
    seq: min, tempC, humidityPct: 90, ax: 0, ay: 0, az: 1, shockG: 0.2, ethylenePpm: null, lat: 19.8, lng: 75.3, reeferOn: false, setpointC: 2, doorOpen: false, batteryPct: 80, format: 'json' as const,
  });

  it('breach start recomputes shelf life for every batch on board (SYN-04); persistence → one CRITICAL alert + EXCURSION traces', async () => {
    const s = setup();
    const persist = 15 * 60_000;
    for (const [m, t] of [[0, 3], [1, 6], [5, 7], [16, 8], [17, 9], [20, 9]] as const) await s.p.process(msg(m, t), persist);
    expect(s.shelfLife.recompute.mock.calls).toEqual([['b1', 'BREACH'], ['b2', 'BREACH']]);
    expect(s.alerts.raise).toHaveBeenCalledTimes(1); // no duplicate alerts for one breach
    expect(s.alerts.raise).toHaveBeenCalledWith(expect.objectContaining({ type: 'TEMP_EXCURSION', severity: 'CRITICAL', tripId: TRIP, notifyDriver: true }));
    expect(s.trace.append.mock.calls.map((c) => [c[1], c[2]])).toEqual([['b1', 'EXCURSION'], ['b2', 'EXCURSION']]);
    expect(s.redis.lists.get('metrics:latency:breach_to_shelf_life_ms')).toHaveLength(1);
    expect(s.realtime.toTrip).toHaveBeenCalledWith(TRIP, 'cargo.status', expect.objectContaining({ tempC: 9, breach: expect.objectContaining({ temp: true }) }));
  });

  it('state survives between packets via Redis (a restarted worker does not re-alert)', async () => {
    const s = setup();
    for (const [m, t] of [[0, 6], [16, 6]] as const) await s.p.process(msg(m, t), 15 * 60_000);
    const p2 = new ThresholdProcessor({} as never, { tripCargo: async () => cargo } as never, s.alerts as never, s.shelfLife as never, s.trace as never, {} as never, s.realtime as never, { $transaction: jest.fn() } as never, s.redis as never);
    await p2.process(msg(18, 7), 15 * 60_000);
    expect(s.alerts.raise).toHaveBeenCalledTimes(1);
  });
});

describe('MaintenanceWorker.checkOffline', () => {
  it('raises DEVICE_OFFLINE once per outage after 5 min of silence; trips just started get grace', async () => {
    const redis = fakeRedis();
    const now = Date.UTC(2026, 10, 14, 6, 0);
    const device = (code: string, startedMinAgo: number) => ({
      deviceCode: code, vehicleId: `veh-${code}`, vehicle: { trips: [{ id: `trip-${code}`, code: `TRP-${code}`, startedAt: new Date(now - startedMinAgo * 60_000) }] },
    });
    await redis.hset('telemetry:lastseen', 'DEV-001', String(now - 6 * 60_000)); // silent 6 min
    await redis.hset('telemetry:lastseen', 'DEV-002', String(now - 60_000)); // fresh
    const prisma = { iotDevice: { findMany: jest.fn().mockResolvedValue([device('DEV-001', 60), device('DEV-002', 60), device('DEV-003', 2)]) } };
    const alerts = { raise: jest.fn().mockResolvedValue({}) };
    const w = new MaintenanceWorker({} as never, prisma as never, alerts as never, {} as never, {} as never, {} as never, {} as never, {} as never, redis as never);
    expect(await w.checkOffline(now)).toBe(1);
    expect(alerts.raise).toHaveBeenCalledWith(expect.objectContaining({ type: 'DEVICE_OFFLINE', severity: 'WARNING', tripId: 'trip-DEV-001' }));
    expect(await w.checkOffline(now + 60_000)).toBe(0); // same outage: no second alert
  });
});

describe('telemetry tiering (SYN-12)', () => {
  it('archives day D−29 (IST) to telemetry-archive/yyyy/mm/dd.csv.gz', () => {
    expect(dayToArchive(new Date('2026-11-14T20:00:00Z'))).toBe('2026-10-17'); // 01:30 IST on the 15th → minus 29 days
    expect(archiveKey('2026-10-17')).toBe('telemetry-archive/2026/10/17.csv.gz');
  });

  it('CSV puts _time first, drops Flux metadata and quotes when needed', () => {
    const csv = rowsToCsv([{ result: '_result', table: 0, _start: 'x', _stop: 'y', _time: 't1', _measurement: 'reefer', temp_c: 3.4, device_id: 'DEV,1' }]);
    expect(csv).toBe('_time,_measurement,device_id,temp_c\nt1,reefer,"DEV,1",3.4\n');
  });

  it('writes a gzip file locally when S3 is not configured', async () => {
    const os = await import('node:os');
    const fs = await import('node:fs/promises');
    const path = await import('node:path');
    const dir = await fs.mkdtemp(path.join(os.tmpdir(), 'iccms-tier-'));
    const influx = { bucket: 'telemetry', query: jest.fn().mockResolvedValue([{ _time: '2026-10-17T00:00:00Z', _measurement: 'reefer', temp_c: 2 }]) };
    const job = new TieringJob(influx as never, { configured: false } as never, { get: (k: string) => (k === 'TIERING_LOCAL_DIR' ? dir : undefined) } as never);
    const r = await job.run('2026-10-17');
    expect(r).toMatchObject({ day: '2026-10-17', rows: 1 });
    expect(gunzipSync(await fs.readFile(r.target)).toString()).toContain('2026-10-17T00:00:00Z,reefer,2');
    expect(influx.query.mock.calls[0][0]).toContain('range(start: 2026-10-16T18:30:00.000Z, stop: 2026-10-17T18:30:00.000Z)'); // IST day
    await fs.rm(dir, { recursive: true });
  });
});
