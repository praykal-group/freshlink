import type { AuthUser } from '../../common/auth/auth-user';
import { AppError } from '../../common/errors/app-error';
import { orderOps, SyncService } from './sync.service';

// M4: duplicate sync op → same result and no second write; ordering; role check; error storage.
const operator = { id: 'op-1', role: 'OPERATOR', siteId: 's1' } as AuthUser;
const driver = { id: 'dr-1', role: 'DRIVER' } as AuthUser;
const BATCH_ID = '0f8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a7b';

function fakePrisma() {
  const rows = new Map<string, { clientOpId: string; userId: string; type: string; result: unknown }>();
  return {
    rows,
    syncOp: {
      findUnique: jest.fn(async ({ where }: { where: { clientOpId: string } }) => rows.get(where.clientOpId) ?? null),
      create: jest.fn(async ({ data }: { data: { clientOpId: string; userId: string; type: string; result: unknown } }) => {
        rows.set(data.clientOpId, data);
        return data;
      }),
    },
  };
}

const tagPayload = { batchId: BATCH_ID, tagType: 'NFC', tagUid: '04A1B2C3' };
const op = (id: string, type: string, payload: Record<string, unknown>, capturedAt = '2026-11-13T10:00:00Z') => ({
  clientOpId: id,
  type: type as never,
  payload,
  capturedAt,
});

describe('orderOps', () => {
  it('sorts by capturedAt and keeps client order for equal times', () => {
    const ops = [
      { id: 'c', capturedAt: '2026-11-13T10:02:00Z' },
      { id: 'a', capturedAt: '2026-11-13T10:00:00Z' },
      { id: 'b1', capturedAt: '2026-11-13T10:01:00Z' },
      { id: 'b2', capturedAt: '2026-11-13T10:01:00Z' },
    ];
    expect(orderOps(ops).map((o) => o.id)).toEqual(['a', 'b1', 'b2', 'c']);
  });
});

describe('SyncService', () => {
  let prisma: ReturnType<typeof fakePrisma>;
  let batches: { attachTag: jest.Mock; create: jest.Mock };
  let trips: { load: jest.Mock; recordEvent: jest.Mock; respondRoute: jest.Mock; arrive: jest.Mock; loadForUser?: jest.Mock };
  let pod: { submit: jest.Mock };
  let alerts: { ack: jest.Mock };
  let telemetry: { writeGps: jest.Mock };
  let sync: SyncService;

  beforeEach(() => {
    prisma = fakePrisma();
    batches = { attachTag: jest.fn().mockResolvedValue({ id: 'tag-1' }), create: jest.fn() };
    trips = { load: jest.fn().mockResolvedValue({ loaded: [] }), recordEvent: jest.fn().mockResolvedValue({ id: 'e' }), respondRoute: jest.fn().mockResolvedValue({ status: 'ACCEPTED' }), arrive: jest.fn().mockResolvedValue({ status: 'ARRIVED' }) };
    pod = { submit: jest.fn().mockResolvedValue({ stored: ['p1'] }) };
    alerts = { ack: jest.fn().mockResolvedValue({ status: 'ACKNOWLEDGED' }) };
    telemetry = { writeGps: jest.fn().mockResolvedValue({ written: 2 }) };
    sync = new SyncService(prisma as never, batches as never, trips as never, pod as never, alerts as never, telemetry as never);
  });

  it('routes driver/operator op types with their own role rules', async () => {
    const TRIP = '9a8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a7b';
    const STOP = '1b8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a7b';
    const r1 = await sync.process(operator, [op('a1111111-1111-4111-8111-111111111111', 'LOAD', { tripId: TRIP, batchIds: [BATCH_ID] })]);
    expect(r1.results[0].status).toBe('APPLIED');
    expect(trips.load).toHaveBeenCalledWith(operator, TRIP, [BATCH_ID]);

    // operator may not send driver ops; driver may not load
    const r2 = await sync.process(operator, [op('a2222222-2222-4222-8222-222222222222', 'ROUTE_ACCEPT', { tripId: TRIP, version: 2 })]);
    const r3 = await sync.process(driver, [op('a3333333-3333-4333-8333-333333333333', 'LOAD', { tripId: TRIP, batchIds: [BATCH_ID] })]);
    expect([r2.results[0].error?.code, r3.results[0].error?.code]).toEqual(['FORBIDDEN_ROLE', 'FORBIDDEN_ROLE']);

    const r4 = await sync.process(driver, [op('a4444444-4444-4444-8444-444444444444', 'ROUTE_ACCEPT', { tripId: TRIP, version: 2 })]);
    expect(r4.results[0].status).toBe('APPLIED');
    expect(trips.respondRoute).toHaveBeenCalledWith(driver, TRIP, 2, true);

    const podBody = {
      receiverName: 'Anil', signatureKey: 'POD_SIGNATURE/2026/11/0f8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a7b.png',
      photoKey: 'POD_PHOTO/2026/11/0f8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a7b.jpg', capturedAt: '2026-11-13T10:00:00Z', lat: 19.8, lng: 75.3,
      items: [{ id: 'b5555555-5555-4555-8555-555555555555', batchId: BATCH_ID, outcome: 'ACCEPTED', acceptedKg: 100, scannedTagUid: '04A1B2C3' }],
    };
    const r5 = await sync.process(driver, [op('a5555555-5555-4555-8555-555555555555', 'POD', { tripId: TRIP, stopId: STOP, ...podBody })]);
    expect(r5.results[0].status).toBe('APPLIED');
    expect(pod.submit).toHaveBeenCalledWith(driver, TRIP, STOP, expect.objectContaining({ receiverName: 'Anil', items: [expect.objectContaining({ outcome: 'ACCEPTED' })] }));
  });

  it('STOP_ARRIVE (M12, offline arrival): driver only, replayed before the POD of that stop', async () => {
    const TRIP = '9a8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a7b';
    const STOP = '1b8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a7b';
    const arrive = { tripId: TRIP, stopId: STOP, arrivedAt: '2026-11-13T09:59:00Z', lat: 19.8, lng: 75.3 };
    const r = await sync.process(driver, [
      op('c2222222-2222-4222-8222-222222222222', 'POD', { tripId: TRIP, stopId: STOP, receiverName: 'x' }, '2026-11-13T10:01:00Z'),
      op('c1111111-1111-4111-8111-111111111111', 'STOP_ARRIVE', arrive, '2026-11-13T10:00:00Z'),
    ]);
    expect(r.results.map((x) => x.type)).toEqual(['STOP_ARRIVE', 'POD']);
    expect(r.results[0].status).toBe('APPLIED');
    expect(trips.arrive).toHaveBeenCalledWith(driver, TRIP, STOP, expect.objectContaining({ arrivedAt: '2026-11-13T09:59:00Z', lat: 19.8 }));
    const bad = await sync.process(operator, [op('c3333333-3333-4333-8333-333333333333', 'STOP_ARRIVE', arrive)]);
    expect(bad.results[0].error?.code).toBe('FORBIDDEN_ROLE');
  });

  it('applies an op once; the duplicate replays the stored result without a second write', async () => {
    const o = op('11111111-1111-4111-8111-111111111111', 'TAG_ATTACH', tagPayload);
    const first = await sync.process(operator, [o]);
    const second = await sync.process(operator, [o]);

    expect(first.results[0]).toMatchObject({ status: 'APPLIED', data: { id: 'tag-1' } });
    expect(second.results[0]).toMatchObject({ status: 'APPLIED', data: { id: 'tag-1' }, replayed: true });
    expect(batches.attachTag).toHaveBeenCalledTimes(1);
    expect(prisma.syncOp.create).toHaveBeenCalledTimes(1);
  });

  it('stores 4xx rejections so retries get the same answer', async () => {
    batches.attachTag.mockRejectedValueOnce(new AppError('TAG_IN_USE', 'in use', 409));
    const o = op('22222222-2222-4222-8222-222222222222', 'TAG_ATTACH', tagPayload);
    expect((await sync.process(operator, [o])).results[0]).toMatchObject({ status: 'REJECTED', error: { code: 'TAG_IN_USE' } });
    expect((await sync.process(operator, [o])).results[0]).toMatchObject({ status: 'REJECTED', replayed: true });
    expect(batches.attachTag).toHaveBeenCalledTimes(1);
  });

  it('does NOT store 5xx errors, so the phone retries', async () => {
    batches.attachTag.mockRejectedValueOnce(new Error('db down')).mockResolvedValueOnce({ id: 'tag-2' });
    const o = op('33333333-3333-4333-8333-333333333333', 'TAG_ATTACH', tagPayload);
    expect((await sync.process(operator, [o])).results[0].status).toBe('ERROR');
    expect((await sync.process(operator, [o])).results[0]).toMatchObject({ status: 'APPLIED', data: { id: 'tag-2' } });
  });

  it('validates the payload (bad batchId / unknown fields → REJECTED)', async () => {
    const bad = await sync.process(operator, [
      op('44444444-4444-4444-8444-444444444444', 'TAG_ATTACH', { batchId: 'x', tagType: 'NFC', tagUid: '04A1B2C3' }),
      op('55555555-5555-4555-8555-555555555555', 'TAG_ATTACH', { ...tagPayload, hack: true }),
    ]);
    expect(bad.results.map((r) => r.status)).toEqual(['REJECTED', 'REJECTED']);
    expect(batches.attachTag).not.toHaveBeenCalled();
  });

  it('applies the same role rules as REST (driver cannot create batches through sync)', async () => {
    const r = await sync.process(driver, [op('66666666-6666-4666-8666-666666666666', 'BATCH_CREATE', {})]);
    expect(r.results[0]).toMatchObject({ status: 'REJECTED', error: { code: 'FORBIDDEN_ROLE' } });
    expect(batches.create).not.toHaveBeenCalled();
  });

  it('GPS_POINTS (driver, trip in progress) and ALERT_ACK', async () => {
    const TRIP = '9a8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a7b';
    const ALERT = '3c8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a7b';
    trips.loadForUser = jest.fn().mockResolvedValue({ id: TRIP, status: 'IN_PROGRESS' });
    const points = [{ lat: 19.8, lng: 75.3, speedKmh: 40, at: '2026-11-14T05:00:00Z' }, { lat: 19.81, lng: 75.31, at: '2026-11-14T05:00:30Z' }];
    const r = await sync.process(driver, [
      op('77777777-7777-4777-8777-777777777777', 'GPS_POINTS', { tripId: TRIP, points }),
      op('78777777-7777-4777-8777-777777777777', 'ALERT_ACK', { alertId: ALERT }),
    ]);
    expect(r.results.map((x) => x.status)).toEqual(['APPLIED', 'APPLIED']);
    expect(telemetry.writeGps).toHaveBeenCalledWith(TRIP, 'dr-1', points);
    expect(alerts.ack).toHaveBeenCalledWith(driver, ALERT);
  });

  it('GPS_POINTS synced after the trip completed: points inside the trip are written, others dropped (M12)', async () => {
    trips.loadForUser = jest.fn().mockResolvedValue({ id: 'x', status: 'COMPLETED', startedAt: new Date('2026-11-14T04:00:00Z'), completedAt: new Date('2026-11-14T08:00:00Z') });
    const pts = [{ lat: 1, lng: 1, at: '2026-11-14T07:59:30Z' }, { lat: 1, lng: 1, at: '2026-11-14T08:05:00Z' }];
    const r = await sync.process(driver, [op('79888888-8888-4888-8888-888888888888', 'GPS_POINTS', { tripId: '9a8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a7b', points: pts })]);
    expect(r.results[0].status).toBe('APPLIED');
    expect(telemetry.writeGps).toHaveBeenCalledWith('9a8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a7b', 'dr-1', [pts[0]]);
    telemetry.writeGps.mockClear();
    const late = await sync.process(driver, [op('79999999-9999-4999-8999-999999999999', 'GPS_POINTS', { tripId: '9a8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a7b', points: [pts[1]] })]);
    expect(late.results[0].status).toBe('APPLIED');
    expect(telemetry.writeGps).not.toHaveBeenCalled();
  });

  it('GPS_POINTS for a trip that has not started is rejected', async () => {
    trips.loadForUser = jest.fn().mockResolvedValue({ id: 'x', status: 'ASSIGNED' });
    const r = await sync.process(driver, [op('79777777-7777-4777-8777-777777777777', 'GPS_POINTS', { tripId: '9a8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a7b', points: [{ lat: 1, lng: 1, at: '2026-11-14T05:00:00Z' }] })]);
    expect(r.results[0]).toMatchObject({ status: 'REJECTED', error: { code: 'INVALID_TRIP_STATUS' } });
  });

  it('refuses a clientOpId that belongs to another user', async () => {
    const o = op('88888888-8888-4888-8888-888888888888', 'TAG_ATTACH', tagPayload);
    await sync.process(operator, [o]);
    const r = await sync.process({ ...operator, id: 'op-2' }, [o]);
    expect(r.results[0]).toMatchObject({ status: 'REJECTED', error: { code: 'DUPLICATE' } });
  });
});
