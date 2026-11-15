import { Reflector } from '@nestjs/core';
import { ROLES } from '../../common/auth/decorators';
import { ControlController } from './control.controller';
import { AT_RISK_HOURS, ControlService } from './control.service';

// M13: control-tower reads.
function prisma(over: Record<string, unknown> = {}) {
  return {
    trip: {
      count: jest.fn().mockResolvedValue(2),
      findMany: jest.fn(async ({ where }) =>
        where.status === 'IN_PROGRESS'
          ? [{ id: 't1', code: 'TRP-1', vehicleId: 'v1', vehicle: { regNo: 'MH20-RF-1001' }, driver: { name: 'Ravi' } }, { id: 't2', code: 'TRP-2', vehicleId: 'v2', vehicle: { regNo: 'MH20-RF-1002' }, driver: null }]
          : [{ driverId: 'd1', code: 'TRP-1' }],
      ),
    },
    alert: { count: jest.fn().mockResolvedValue(1) },
    batch: { count: jest.fn().mockResolvedValue(4) },
    proofOfDelivery: { groupBy: jest.fn().mockResolvedValue([{ tripStopId: 's1' }, { tripStopId: 's2' }, { tripStopId: 's3' }]), aggregate: jest.fn().mockResolvedValue({ _sum: { acceptedKg: '310.5' } }) },
    user: { findMany: jest.fn().mockResolvedValue([{ id: 'd1', name: 'Ravi', phone: '+91', siteId: 's' }, { id: 'd2', name: 'Sunil', phone: '+91', siteId: 's' }]) },
    appRelease: { findMany: jest.fn().mockResolvedValue([{ id: 'r1', flavor: 'driver', versionCode: 3, sizeBytes: BigInt(33625119) }]) },
    ...over,
  };
}

describe('ControlService', () => {
  it('dashboard KPIs (Section 10.6 #1) with the queries they are defined by', async () => {
    const p = prisma();
    const telemetry = { lastReading: jest.fn(async (v: string) => (v === 'v1' ? { lat: 19.8, lng: 75.3, tempC: 2.4, ts: '2026-11-15T09:00:00Z' } : null)) };
    const r = await new ControlService(p as never, telemetry as never).summary(new Date('2026-11-15T06:30:00Z'));
    expect(r.kpis).toEqual({ activeTrips: 2, openCriticalAlerts: 1, atRiskBatches: 4, deliveriesToday: 3, spoilageAvoidedKg: 310.5 });
    expect(p.alert.count).toHaveBeenCalledWith({ where: { severity: 'CRITICAL', status: { in: ['OPEN', 'ESCALATED'] } } });
    expect(p.batch.count.mock.calls[0][0].where.remainingShelfLifeH).toEqual({ lt: AT_RISK_HOURS });
    expect(p.batch.count.mock.calls[0][0].where.status.in).not.toContain('DELIVERED');
    const pod = p.proofOfDelivery.groupBy.mock.calls[0][0].where.capturedAt;
    expect([pod.gte.toISOString(), pod.lt.toISOString()]).toEqual(['2026-11-14T18:30:00.000Z', '2026-11-15T18:30:00.000Z']); // IST day
    expect(p.proofOfDelivery.aggregate.mock.calls[0][0].where.tripStop.type.in).toEqual(['DIVERSION_DROP', 'COLD_STORAGE_DROP', 'RESCUE_DROP']);
    expect(r.vehicles).toEqual([
      { vehicleId: 'v1', regNo: 'MH20-RF-1001', tripId: 't1', tripCode: 'TRP-1', driverName: 'Ravi', lat: 19.8, lng: 75.3, tempC: 2.4, at: '2026-11-15T09:00:00Z' },
      { vehicleId: 'v2', regNo: 'MH20-RF-1002', tripId: 't2', tripCode: 'TRP-2', driverName: null, lat: null, lng: null, tempC: null, at: null },
    ]);
  });

  it('without Redis / telemetry the KPIs still come back, positions unknown', async () => {
    const r = await new ControlService(prisma() as never).summary();
    expect(r.vehicles.every((v) => v.lat === null)).toBe(true);
  });

  it('drivers with their current trip; releases with sizes as numbers and an unknown flavor ignored', async () => {
    const p = prisma();
    const s = new ControlService(p as never);
    expect((await s.drivers()).items.map((d) => [d.name, d.busyTripCode])).toEqual([['Ravi', 'TRP-1'], ['Sunil', null]]);
    expect((await s.releases('driver')).items[0].sizeBytes).toBe(33625119);
    await s.releases('hacker');
    expect(p.appRelease.findMany.mock.calls[1][0].where).toEqual({ isActive: true });
  });

  it('every route is MANAGER / ADMIN only', () => {
    expect(new Reflector().get(ROLES, ControlController)).toEqual(['MANAGER', 'ADMIN']);
  });
});
