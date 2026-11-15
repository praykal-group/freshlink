import { Reflector } from '@nestjs/core';
import type { AuthUser } from '../../common/auth/auth-user';
import { ROLES } from '../../common/auth/decorators';
import { AppError } from '../../common/errors/app-error';
import { OrdersController } from '../orders/orders.controller';
import { batchStatusFor, checkOutcome, PodService } from '../pod/pod.service';
import { TripsService } from './trips.service';

const TRIP = '9a8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a7b';
const STOP = '1b8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a7b';
const B1 = '0f8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a7b';
const driver = { id: 'drv-1', role: 'DRIVER', siteId: 'dc' } as AuthUser;
const operator = { id: 'op-1', role: 'OPERATOR', siteId: 'depot' } as AuthUser;

async function code(p: Promise<unknown>) {
  try {
    await p;
    return 'OK';
  } catch (e) {
    return e instanceof AppError ? `${e.getStatus()} ${e.code}` : String(e);
  }
}

function trip(over: Record<string, unknown> = {}) {
  return { id: TRIP, code: 'TRP-20261114-0001', status: 'PRE_CHECK_DONE', driverId: 'drv-1', vehicleId: 'veh-1', depotSiteId: 'depot', boundDeviceId: null, currentRouteVersion: 1, distanceKm: 100, ...over };
}

function setup(t: Record<string, unknown> | null = trip()) {
  const tx = {
    trip: { updateMany: jest.fn().mockResolvedValue({ count: 1 }), findUniqueOrThrow: jest.fn().mockResolvedValue(t), update: jest.fn() },
    vehicle: { update: jest.fn() },
    tripStop: { updateMany: jest.fn(), findMany: jest.fn().mockResolvedValue([]) },
    tripEvent: { create: jest.fn() },
    batch: { update: jest.fn(), findUniqueOrThrow: jest.fn() },
    dispatchOrder: { updateMany: jest.fn() },
    tripBatch: { findUnique: jest.fn(), create: jest.fn() },
  };
  const prisma = {
    trip: { findUnique: jest.fn().mockResolvedValue(t), findFirst: jest.fn().mockResolvedValue(null) },
    tripBatch: { findMany: jest.fn().mockResolvedValue([{ batchId: B1 }]) },
    tripStop: { findMany: jest.fn().mockResolvedValue([{ orderId: 'o1' }]) },
    orderBatch: { findMany: jest.fn().mockResolvedValue([{ batchId: B1 }]) },
    vehicle: { findUniqueOrThrow: jest.fn().mockResolvedValue({ regNo: 'MH20-RF-1001' }) },
    tripEvent: { findUnique: jest.fn().mockResolvedValue(null), create: jest.fn(async ({ data }) => data) },
    user: { findUniqueOrThrow: jest.fn().mockResolvedValue({ name: 'Ravi', phone: '+919999900011', emergencyContactPhone: '+919811111111' }) },
    alert: { create: jest.fn(async ({ data }) => ({ id: 'alert-1', ...data })) },
    $transaction: jest.fn(async (fn: (t: typeof tx) => unknown) => fn(tx)),
  };
  const realtime = { toManagers: jest.fn(), toTrip: jest.fn(), toUser: jest.fn() };
  const sms = { send: jest.fn().mockResolvedValue({}) };
  const events = { publish: jest.fn() };
  const trace = { append: jest.fn() };
  const alerts = { raise: jest.fn(async (a: Record<string, unknown>) => ({ id: 'alert-1', ...a })) };
  const service = new TripsService(prisma as never, trace as never, { release: jest.fn() } as never, { verifyOwnUpload: jest.fn() } as never, sms as never, {} as never, realtime as never, events as never, alerts as never);
  return { service, prisma, tx, realtime, sms, trace, alerts };
}

describe('TripsService.start', () => {
  it('cannot start a trip without the pre-check → 409 PRE_CHECK_REQUIRED', async () => {
    const s = setup(trip({ status: 'ASSIGNED' }));
    expect(await code(s.service.start(driver, TRIP, 'phone-A'))).toBe('409 PRE_CHECK_REQUIRED');
  });

  it('a second device → 409 TRIP_ON_OTHER_DEVICE', async () => {
    const s = setup(trip({ boundDeviceId: 'phone-A' }));
    expect(await code(s.service.start(driver, TRIP, 'phone-B'))).toBe('409 TRIP_ON_OTHER_DEVICE');
  });

  it('one active trip per driver and per vehicle', async () => {
    const s = setup();
    s.prisma.trip.findFirst.mockResolvedValueOnce({ code: 'TRP-X', driverId: 'drv-1' });
    expect(await code(s.service.start(driver, TRIP, 'phone-A'))).toBe('409 DRIVER_ON_OTHER_TRIP');
    s.prisma.trip.findFirst.mockResolvedValueOnce({ code: 'TRP-Y', driverId: 'someone-else' });
    expect(await code(s.service.start(driver, TRIP, 'phone-A'))).toBe('409 VEHICLE_IN_USE');
  });

  it('another driver cannot touch the trip', async () => {
    expect(await code(setup().service.start({ ...driver, id: 'drv-2' }, TRIP, 'x'))).toBe('403 FORBIDDEN_TRIP');
  });

  it('starts: binds the device, vehicle in use, batches IN_TRANSIT with DEPARTED trace, managers notified', async () => {
    const s = setup();
    await s.service.start(driver, TRIP, 'phone-A');
    expect(s.tx.trip.updateMany).toHaveBeenCalledWith({ where: { id: TRIP, status: 'PRE_CHECK_DONE' }, data: expect.objectContaining({ status: 'IN_PROGRESS', boundDeviceId: 'phone-A' }) });
    expect(s.tx.vehicle.update).toHaveBeenCalledWith({ where: { id: 'veh-1' }, data: { status: 'IN_USE' } });
    expect(s.tx.batch.update).toHaveBeenCalledWith({ where: { id: B1 }, data: { status: 'IN_TRANSIT' } });
    expect(s.trace.append).toHaveBeenCalledWith(s.tx, B1, 'DEPARTED', { tripCode: 'TRP-20261114-0001' }, 'drv-1', expect.any(Date));
    expect(s.realtime.toManagers).toHaveBeenCalledWith('trip.updated', expect.objectContaining({ status: 'IN_PROGRESS' }));
  });
});

describe('TripsService.load (FO-FR-11)', () => {
  it('rejects batches not allocated to this trip (wrong-batch warning)', async () => {
    const s = setup(trip({ status: 'ASSIGNED' }));
    s.prisma.orderBatch.findMany.mockResolvedValueOnce([]);
    const r = await s.service.load(operator, TRIP, [B1]).catch((e: AppError) => e);
    expect(r).toMatchObject({ code: 'BATCH_NOT_ON_TRIP', details: { batchIds: [B1] } });
  });

  it('operators load only at the trip depot', async () => {
    expect(await code(setup(trip({ status: 'ASSIGNED' })).service.load({ ...operator, siteId: 'other' }, TRIP, [B1]))).toBe('403 FORBIDDEN_SITE');
  });
});

describe('TripsService SOS (DA-FR-14)', () => {
  it('raises a CRITICAL alert (manager chain) and texts the emergency contact with the location', async () => {
    const s = setup(trip({ status: 'IN_PROGRESS' }));
    await s.service.recordEvent(driver, TRIP, { id: 'e5555555-5555-4555-8555-555555555555', type: 'SOS', lat: 19.8762, lng: 75.3433, occurredAt: '2026-11-14T05:00:00Z' });
    expect(s.alerts.raise).toHaveBeenCalledWith(expect.objectContaining({ type: 'SOS', severity: 'CRITICAL', tripId: TRIP, vehicleId: 'veh-1' }));
    expect(s.sms.send).toHaveBeenCalledWith('+919811111111', expect.stringContaining('https://maps.google.com/?q=19.876200,75.343300'), expect.objectContaining({ priority: 'alert' }));
  });

  it('replaying the same event id is idempotent (no second alert)', async () => {
    const s = setup(trip({ status: 'IN_PROGRESS' }));
    s.prisma.tripEvent.findUnique.mockResolvedValueOnce({ id: 'e1', tripId: TRIP });
    await s.service.recordEvent(driver, TRIP, { id: 'e1', type: 'SOS', occurredAt: '2026-11-14T05:00:00Z' } as never);
    expect(s.alerts.raise).not.toHaveBeenCalled();
  });
});

describe('order approval is manager-only', () => {
  it('OrdersController routes require MANAGER or ADMIN', () => {
    const roles = new Reflector().getAllAndOverride(ROLES, [OrdersController.prototype.approve, OrdersController]);
    expect(roles).toEqual(['MANAGER', 'ADMIN']);
  });
});

describe('PoD rules (DA-FR-12)', () => {
  it('outcome / quantity rules', () => {
    expect(checkOutcome({ outcome: 'ACCEPTED', acceptedKg: 100 }, 100)).toBeNull();
    expect(checkOutcome({ outcome: 'ACCEPTED', acceptedKg: 90 }, 100)).toMatch(/full/);
    expect(checkOutcome({ outcome: 'PARTIAL', acceptedKg: 60, reason: 'bruised' }, 100)).toBeNull();
    expect(checkOutcome({ outcome: 'PARTIAL', acceptedKg: 100, reason: 'x' }, 100)).toMatch(/PARTIAL/);
    expect(checkOutcome({ outcome: 'REJECTED', acceptedKg: 0 }, 100)).toMatch(/reason/);
  });

  it('maps outcomes to batch statuses', () => {
    expect([batchStatusFor('ACCEPTED'), batchStatusFor('PARTIAL'), batchStatusFor('REJECTED')]).toEqual(['DELIVERED', 'PARTIALLY_DELIVERED', 'REJECTED']);
  });
});

describe('PodService.submit', () => {
  const sig = 'POD_SIGNATURE/2026/11/0f8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a7b.png';
  const photo = 'POD_PHOTO/2026/11/0f8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a7b.jpg';
  const POD1 = 'c1111111-1111-4111-8111-111111111111';
  const dto = (over: Record<string, unknown> = {}) => ({
    receiverName: 'Anil', signatureKey: sig, photoKey: photo, capturedAt: '2026-11-14T08:00:00Z', lat: 19.8, lng: 75.3,
    items: [{ id: POD1, batchId: B1, outcome: 'PARTIAL', acceptedKg: 60, reason: 'two crates bruised', scannedTagUid: '04A1B2C3', ...over }],
  });

  function podSetup(tag = '04A1B2C3') {
    const tx = {
      tripStop: { update: jest.fn(), updateMany: jest.fn() },
      proofOfDelivery: { create: jest.fn(), findMany: jest.fn().mockResolvedValue([{ batchId: B1 }]) },
      batch: { update: jest.fn() },
      tripBatch: { update: jest.fn(), upsert: jest.fn(), findMany: jest.fn().mockResolvedValue([{ batchId: B1 }]) },
      dispatchOrder: { update: jest.fn() },
    };
    const prisma = {
      tripStop: { findUnique: jest.fn().mockResolvedValue({ id: STOP, tripId: TRIP, routeVersion: 1, type: 'DROP', status: 'ARRIVED', siteId: 'dc-1', orderId: 'o1', site: { code: 'DC-CSN' } }) },
      proofOfDelivery: { findMany: jest.fn().mockResolvedValue([]) },
      tripBatch: { findMany: jest.fn().mockResolvedValue([{ batchId: B1, batch: { id: B1, code: 'FSH-1', weightKg: 100, tags: [{ tagUid: tag }] } }]) },
      orderBatch: { findMany: jest.fn().mockResolvedValue([{ batchId: B1 }]) },
      $transaction: jest.fn(async (fn: (t: typeof tx) => unknown) => fn(tx)),
    };
    const trips = {
      loadForUser: jest.fn().mockResolvedValue(trip({ status: 'IN_PROGRESS' })),
      assertCan: jest.fn(),
      emissionFactor: jest.fn().mockResolvedValue(0.9),
      completeIfDone: jest.fn().mockResolvedValue(true),
      publishTripDone: jest.fn(),
    };
    const trace = { append: jest.fn() };
    const service = new PodService(prisma as never, trips as never, { verifyOwnUpload: jest.fn() } as never, trace as never, { publish: jest.fn() } as never);
    return { service, tx, trace, trips, prisma };
  }

  it('PARTIAL → batch PARTIALLY_DELIVERED at the stop site + DELIVERED trace with the outcome; stop, order and trip complete', async () => {
    const s = podSetup();
    const r = await s.service.submit(driver, TRIP, STOP, dto() as never);
    expect(s.tx.batch.update).toHaveBeenCalledWith({ where: { id: B1 }, data: { status: 'PARTIALLY_DELIVERED', currentSiteId: 'dc-1' } });
    expect(s.trace.append).toHaveBeenCalledWith(s.tx, B1, 'DELIVERED', expect.objectContaining({ outcome: 'PARTIAL', acceptedKg: 60, weightKg: 100, siteCode: 'DC-CSN' }), 'drv-1', expect.any(Date));
    expect(s.tx.tripStop.update).toHaveBeenCalledWith({ where: { id: STOP }, data: expect.objectContaining({ status: 'COMPLETED' }) });
    expect(s.tx.dispatchOrder.update).toHaveBeenCalledWith({ where: { id: 'o1' }, data: { status: 'DELIVERED' } });
    expect(s.trips.completeIfDone).toHaveBeenCalledWith(s.tx, TRIP, 0.9);
    expect(r).toMatchObject({ stored: [POD1], stopCompleted: true, tripCompleted: true });
  });

  it('REJECTED → batch REJECTED + REJECTED trace, batch stays where it was', async () => {
    const s = podSetup();
    await s.service.submit(driver, TRIP, STOP, dto({ outcome: 'REJECTED', acceptedKg: 0, reason: 'smell' }) as never);
    expect(s.tx.batch.update).toHaveBeenCalledWith({ where: { id: B1 }, data: { status: 'REJECTED' } });
    expect(s.trace.append).toHaveBeenCalledWith(s.tx, B1, 'REJECTED', expect.objectContaining({ reason: 'smell' }), 'drv-1', expect.any(Date));
  });

  it('a wrong crate scan → 409 TAG_MISMATCH, nothing stored', async () => {
    const s = podSetup('E200-OTHER');
    expect(await code(s.service.submit(driver, TRIP, STOP, dto() as never))).toBe('409 TAG_MISMATCH');
    expect(s.tx.proofOfDelivery.create).not.toHaveBeenCalled();
  });

  it('the batch code from the label QR also counts as a scan', async () => {
    const s = podSetup('E200-OTHER');
    expect(await code(s.service.submit(driver, TRIP, STOP, dto({ scannedTagUid: 'FSH-1' }) as never))).toBe('OK');
  });

  it('RESCUE_DROP hands the batches over to the rescue trip (RESCUED trace, still IN_TRANSIT) and closes its pickup', async () => {
    const s = podSetup();
    s.prisma.tripStop.findUnique.mockResolvedValue({ id: STOP, tripId: TRIP, routeVersion: 1, type: 'RESCUE_DROP', status: 'ARRIVED', siteId: null, orderId: null, site: null });
    Object.assign(s.prisma, { trip: { findUniqueOrThrow: jest.fn().mockResolvedValue({ id: 'trip-2', code: 'TRP-2' }) } });
    const incidents = { rescueTripFor: jest.fn().mockResolvedValue('trip-2'), onDropCompleted: jest.fn().mockResolvedValue(undefined) };
    const service = new PodService(s.prisma as never, s.trips as never, { verifyOwnUpload: jest.fn() } as never, s.trace as never, { publish: jest.fn() } as never, incidents as never);

    expect(await code(service.submit(driver, TRIP, STOP, dto() as never))).toBe('422 INVALID_POD'); // whole batches only
    await service.submit(driver, TRIP, STOP, dto({ outcome: 'ACCEPTED', acceptedKg: 100, reason: undefined }) as never);
    expect(s.tx.batch.update).toHaveBeenCalledWith({ where: { id: B1 }, data: { status: 'IN_TRANSIT' } });
    expect(s.tx.tripBatch.upsert).toHaveBeenCalledWith(expect.objectContaining({ create: expect.objectContaining({ tripId: 'trip-2', batchId: B1, loadedBy: 'drv-1' }) }));
    expect(s.trace.append).toHaveBeenCalledWith(s.tx, B1, 'RESCUED', expect.objectContaining({ toTripCode: 'TRP-2' }), 'drv-1', expect.any(Date));
    expect(s.trace.append).not.toHaveBeenCalledWith(s.tx, B1, 'DELIVERED', expect.anything(), expect.anything(), expect.anything());
    expect(s.tx.tripStop.updateMany).toHaveBeenCalledWith(expect.objectContaining({ where: expect.objectContaining({ tripId: 'trip-2', type: 'RESCUE_PICKUP' }) }));
    expect(incidents.onDropCompleted).toHaveBeenCalledWith(TRIP, 'RESCUE_DROP');
  });

  it('replayed PoD rows are not stored twice', async () => {
    const s = podSetup();
    s.prisma.proofOfDelivery.findMany.mockResolvedValueOnce([{ id: POD1 }]);
    const r = await s.service.submit(driver, TRIP, STOP, dto() as never);
    expect(r).toMatchObject({ stored: [], replayed: [POD1] });
    expect(s.prisma.$transaction).not.toHaveBeenCalled();
  });
});

describe('TripsService.route (DA-FR-08 reroute proposal)', () => {
  it('returns old and new stops with names, the extra km and whether the driver may decline', async () => {
    const s = setup(trip({ status: 'IN_PROGRESS', currentRouteVersion: 1 }));
    const plans: Record<string, unknown> = { accepted: { version: 1, fitness: 120.04, reason: 'INITIAL', status: 'ACCEPTED' }, pending: { version: 2, fitness: 131.26, reason: 'DIVERSION', status: 'PROPOSED' } };
    (s.prisma as Record<string, unknown>).routePlan = { findFirst: jest.fn(async ({ where }) => (where.status === 'PROPOSED' ? plans.pending : plans.accepted)) };
    s.prisma.tripStop.findMany = jest.fn(async ({ where }) =>
      where.routeVersion === 1 ? [{ id: 's1', seq: 1, site: { code: 'DC-CSN', name: 'Sambhajinagar DC' }, buyer: null }] : [{ id: 's9', seq: 1, site: null, buyer: { name: 'Jalna Fresh' } }],
    ) as never;
    const r = await s.service.route(driver, TRIP);
    expect(r.pending).toMatchObject({ version: 2, distanceKm: 131.3, extraKm: 11.2, canDecline: false, stopRows: [{ buyer: { name: 'Jalna Fresh' } }] });
    expect(r.accepted).toMatchObject({ distanceKm: 120, stopRows: [{ site: { name: 'Sambhajinagar DC' } }] });
    expect(s.prisma.tripStop.findMany).toHaveBeenCalledWith(expect.objectContaining({ where: expect.objectContaining({ status: { not: 'CANCELLED' } }) }));
  });

  it('a DELAY replan can be declined; no proposal → pending null', async () => {
    const s = setup(trip({ status: 'IN_PROGRESS' }));
    (s.prisma as Record<string, unknown>).routePlan = { findFirst: jest.fn(async ({ where }) => (where.status === 'PROPOSED' ? { version: 2, fitness: 100, reason: 'DELAY' } : { version: 1, fitness: 100 })) };
    expect((await s.service.route(driver, TRIP)).pending).toMatchObject({ canDecline: true, extraKm: 0 });
    (s.prisma as Record<string, unknown>).routePlan = { findFirst: jest.fn(async ({ where }) => (where.status === 'PROPOSED' ? null : { version: 1, fitness: 100 })) };
    expect((await s.service.route(driver, TRIP)).pending).toBeNull();
  });
});

describe('TripsService.detail (driver app, M12)', () => {
  it('each drop lists the batches it expects (null for open drops) and each batch its tag UIDs', async () => {
    const s = setup(trip({ status: 'IN_PROGRESS' }));
    s.prisma.tripStop.findMany = jest.fn().mockResolvedValue([
      { id: 'p', seq: 1, type: 'PICKUP', orderId: null, site: { code: 'DEP', name: 'Depot' }, buyer: null },
      { id: 'd1', seq: 2, type: 'DROP', orderId: 'o1', site: { code: 'DC', name: 'DC' }, buyer: null },
      { id: 'dv', seq: 3, type: 'DIVERSION_DROP', orderId: 'o2', site: null, buyer: { name: 'Jalna Fresh' } },
    ]) as never;
    s.prisma.tripBatch.findMany = jest.fn().mockResolvedValue([
      { batchId: B1, loadedAt: null, unloadedAt: null, batch: { code: 'FSH-1', productId: 'p1', weightKg: '120.5', status: 'IN_TRANSIT', currentGrade: 'A', product: { code: 'ROHU', name: 'Rohu' }, tags: [{ tagUid: '04A1' }, { tagUid: 'E200' }] } },
    ]) as never;
    s.prisma.orderBatch.findMany = jest.fn().mockResolvedValue([{ orderId: 'o1', batchId: B1 }]) as never;
    (s.prisma.vehicle as Record<string, unknown>).findUnique = jest.fn().mockResolvedValue({ id: 'veh-1', regNo: 'MH20', capacityKg: '3000' });
    (s.prisma.user as Record<string, unknown>).findUnique = jest.fn().mockResolvedValue({ id: 'drv-1', name: 'Ravi', phone: '+91' });
    const d = await s.service.detail(driver, TRIP);
    expect(d.stops.map((x) => x.batchIds)).toEqual([null, [B1], null]);
    expect(d.batches[0]).toMatchObject({ batchId: B1, code: 'FSH-1', weightKg: 120.5, tagUids: ['04A1', 'E200'], product: { code: 'ROHU' } });
    expect(d.batches[0]).not.toHaveProperty('tags');
    expect(d.stops[2]).toMatchObject({ buyer: { name: 'Jalna Fresh' } });
  });
});
