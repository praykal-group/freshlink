import { OperatorService } from './operator.service';

const op = { id: 'op-1', role: 'OPERATOR', siteId: 'site-1' } as never;

describe('OperatorService (M11 operator app reads)', () => {
  it('summary counts today (IST) at the operator site only', async () => {
    const prisma = {
      site: { findUnique: jest.fn().mockResolvedValue({ id: 'site-1', code: 'DCK-PTN', name: 'Paithan Dock', type: 'DOCK' }) },
      batch: { count: jest.fn().mockResolvedValueOnce(7).mockResolvedValueOnce(4) },
      qualityGrade: { count: jest.fn().mockResolvedValue(5) },
      tripBatch: { count: jest.fn().mockResolvedValue(3) },
    };
    const r = await new OperatorService(prisma as never).summary(op, '2026-11-15');
    expect(r).toEqual({ date: '2026-11-15', site: expect.objectContaining({ code: 'DCK-PTN' }), registered: 7, graded: 5, stored: 4, dispatched: 3 });
    const registered = prisma.batch.count.mock.calls[0][0].where;
    expect(registered.sourceSiteId).toBe('site-1');
    // 2026-11-15 00:00 IST = 2026-11-14T18:30Z
    expect(registered.createdAt.gte.toISOString()).toBe('2026-11-14T18:30:00.000Z');
    expect(registered.createdAt.lt.toISOString()).toBe('2026-11-15T18:30:00.000Z');
    expect(prisma.tripBatch.count.mock.calls[0][0].where.trip).toEqual({ depotSiteId: 'site-1' });
  });

  it('trips: loadable trips at the depot with allocated batches of the CURRENT route version and loaded ids', async () => {
    const prisma = {
      trip: {
        findMany: jest.fn().mockResolvedValue([
          {
            id: 't1', code: 'TRP-1', status: 'ASSIGNED', plannedStart: new Date('2026-11-15T01:00:00Z'), currentRouteVersion: 2,
            vehicle: { regNo: 'MH20-RF-1001', capacityKg: '3000' }, driver: { name: 'Ravi' }, batches: [{ batchId: 'b1' }],
            stops: [
              { routeVersion: 2, order: { batches: [{ batch: { id: 'b1', code: 'FSH-1', weightKg: '120' } }, { batch: { id: 'b2', code: 'FSH-2', weightKg: '80' } }] } },
              { routeVersion: 1, order: { batches: [{ batch: { id: 'old', code: 'FSH-0', weightKg: '10' } }] } },
              { routeVersion: 2, order: { batches: [{ batch: { id: 'b1', code: 'FSH-1', weightKg: '120' } }] } },
            ],
          },
        ]),
      },
    };
    const r = await new OperatorService(prisma as never).trips(op);
    expect(r.items[0]).toMatchObject({ code: 'TRP-1', vehicle: { regNo: 'MH20-RF-1001', capacityKg: 3000 }, driverName: 'Ravi', loadedBatchIds: ['b1'] });
    expect(r.items[0].allocated).toEqual([{ id: 'b1', code: 'FSH-1', weightKg: 120 }, { id: 'b2', code: 'FSH-2', weightKg: 80 }]);
    const where = prisma.trip.findMany.mock.calls[0][0].where;
    expect(where.depotSiteId).toBe('site-1');
    expect(where.status.in).toEqual(['PLANNED', 'ASSIGNED', 'PRE_CHECK_DONE']);
  });

  it('an account without a site gets 422 NO_SITE', async () => {
    const svc = new OperatorService({} as never);
    await expect(svc.summary({ ...(op as object), siteId: null } as never)).rejects.toMatchObject({ code: 'NO_SITE' });
  });
});
