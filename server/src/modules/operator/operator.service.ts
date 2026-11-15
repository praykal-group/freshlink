import { HttpStatus, Injectable } from '@nestjs/common';
import type { AuthUser } from '../../common/auth/auth-user';
import { AppError } from '../../common/errors/app-error';
import { istAt, istDay } from '../../common/ist';
import { PrismaService } from '../../infra/prisma/prisma.service';

const DAY = /^\d{4}-\d{2}-\d{2}$/;
/** Trips an operator can still load (Section 10.4 "Load truck: pick today's trip"). */
const LOADABLE = ['PLANNED', 'ASSIGNED', 'PRE_CHECK_DONE'] as const;

/**
 * Operator app reads (M11): today's counts for the home screen and today's trips at the depot with
 * the batches allocated to each, so the load screen can warn about a wrong batch even offline.
 * Always scoped to the operator's own site.
 */
@Injectable()
export class OperatorService {
  constructor(private readonly prisma: PrismaService) {}

  private site(user: AuthUser): string {
    if (!user.siteId) throw new AppError('NO_SITE', 'This account is not linked to a site', HttpStatus.UNPROCESSABLE_ENTITY);
    return user.siteId;
  }

  private range(date?: string) {
    const day = date && DAY.test(date) ? date : istDay(new Date());
    return { day, from: istAt(day), to: istAt(day, '24:00') };
  }

  /** Home: registered / graded / stored / dispatched today at the operator's site (Section 10.4). */
  async summary(user: AuthUser, date?: string) {
    const siteId = this.site(user);
    const { day, from, to } = this.range(date);
    const [site, registered, graded, stored, dispatched] = await Promise.all([
      this.prisma.site.findUnique({ where: { id: siteId }, select: { id: true, code: true, name: true, type: true } }),
      this.prisma.batch.count({ where: { sourceSiteId: siteId, createdAt: { gte: from, lt: to } } }),
      this.prisma.qualityGrade.count({ where: { batch: { currentSiteId: siteId }, createdAt: { gte: from, lt: to } } }),
      this.prisma.batch.count({ where: { currentSiteId: siteId, status: 'STORED' } }),
      this.prisma.tripBatch.count({ where: { loadedAt: { gte: from, lt: to }, trip: { depotSiteId: siteId } } }),
    ]);
    return { date: day, site, registered, graded, stored, dispatched };
  }

  /** Load truck: today's loadable trips at this depot, with allocated and already loaded batches. */
  async trips(user: AuthUser, date?: string) {
    const siteId = this.site(user);
    const { day, from, to } = this.range(date);
    const trips = await this.prisma.trip.findMany({
      where: { depotSiteId: siteId, status: { in: [...LOADABLE] }, plannedStart: { gte: from, lt: to } },
      include: {
        vehicle: { select: { regNo: true, capacityKg: true } },
        driver: { select: { name: true } },
        batches: { select: { batchId: true } },
        stops: { where: { orderId: { not: null } }, select: { routeVersion: true, order: { select: { batches: { select: { batch: { select: { id: true, code: true, weightKg: true } } } } } } } },
      },
      orderBy: { plannedStart: 'asc' },
    });
    return {
      date: day,
      items: trips.map((t) => {
        const allocated = new Map<string, { id: string; code: string; weightKg: number }>();
        for (const s of t.stops.filter((x) => x.routeVersion === t.currentRouteVersion)) {
          for (const ob of s.order?.batches ?? []) allocated.set(ob.batch.id, { id: ob.batch.id, code: ob.batch.code, weightKg: Number(ob.batch.weightKg) });
        }
        return {
          id: t.id,
          code: t.code,
          status: t.status,
          plannedStart: t.plannedStart,
          vehicle: { regNo: t.vehicle.regNo, capacityKg: Number(t.vehicle.capacityKg) },
          driverName: t.driver?.name ?? null,
          allocated: [...allocated.values()],
          loadedBatchIds: t.batches.map((b) => b.batchId),
        };
      }),
    };
  }
}
