import { HttpStatus, Injectable, Logger } from '@nestjs/common';
import type { Prisma } from '@prisma/client';
import type { AuthUser } from '../../common/auth/auth-user';
import { nextCode } from '../../common/codes';
import { AppError } from '../../common/errors/app-error';
import { istAt, ymd } from '../../common/ist';
import { EventBus } from '../../infra/events/event-bus.service';
import { MlCallError, MlClient } from '../../infra/ml/ml-client.service';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { ForecastService } from '../forecast/forecast.service';
import { ALLOCATABLE, OrdersService } from '../orders/orders.service';
import { RealtimeService } from '../realtime/realtime.service';
import { allocateFefo, type Available, type Need, shortfall } from './fefo';

/** Delivery window for planner orders, IST (D-76). */
export const PLAN_WINDOW = { start: '06:00', end: '18:00' };
const SOURCE_TYPES = ['DOCK', 'FARM_GATE', 'COLD_STORAGE', 'WAREHOUSE'] as const;
const ML_TIMEOUT_MS = 15_000;

interface MlRoute {
  vehicleId: string;
  stops: { id: string; eta: string; lateMin: number }[];
  distanceKm: number;
  loadKg: number;
}
interface MlOptimize {
  routes: MlRoute[];
  fitness: number;
  distanceKm: number;
  feasible: boolean;
  violations: Record<string, number>;
  latencyMs: number;
  travelProvider: string;
}

@Injectable()
export class PlanningService {
  private readonly logger = new Logger(PlanningService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly forecasts: ForecastService,
    private readonly orders: OrdersService,
    private readonly ml: MlClient,
    private readonly events: EventBus,
    private readonly realtime: RealtimeService,
  ) {}

  /**
   * POST /planning/run (W-3, Section 6.5): need = forecast − on-hand − in-transit per centre and
   * product; FEFO allocation of free batches at source sites; one DRAFT order per
   * (source, centre, product). Re-running a date replaces that date's PLANNER drafts.
   */
  async run(user: AuthUser, date: string) {
    const dayStart = istAt(date);
    const dayEnd = istAt(date, '24:00');
    const [centres, products] = await Promise.all([
      this.prisma.site.findMany({ where: { active: true, type: 'DISTRIBUTION_CENTRE' } }),
      this.prisma.product.findMany({ where: { active: true }, select: { id: true, code: true } }),
    ]);
    const forecast = await this.forecasts.query({ from: date, to: date });
    const fc = new Map(forecast.map((f) => [`${f.siteId}|${f.productId}`, f.predictedKg]));

    return this.prisma.$transaction(
      async (tx) => {
        // Replace this date's previous planner drafts (their batches become free again).
        const old = await tx.dispatchOrder.findMany({
          where: { origin: 'PLANNER', status: 'DRAFT', windowStart: { gte: dayStart, lt: dayEnd } },
          select: { id: true },
        });
        if (old.length) {
          await tx.orderBatch.deleteMany({ where: { orderId: { in: old.map((o) => o.id) } } });
          await tx.dispatchOrder.deleteMany({ where: { id: { in: old.map((o) => o.id) } } });
        }

        const centreIds = centres.map((c) => c.id);
        const [onHand, inTransit] = await Promise.all([
          tx.batch.groupBy({
            by: ['currentSiteId', 'productId'],
            where: { currentSiteId: { in: centreIds }, status: { in: [...ALLOCATABLE] } },
            _sum: { weightKg: true },
          }),
          tx.dispatchOrder.groupBy({
            by: ['destinationSiteId', 'productId'],
            where: { destinationSiteId: { in: centreIds }, status: { in: ['APPROVED', 'PLANNED', 'IN_TRANSIT'] }, windowStart: { gte: dayStart, lt: dayEnd } },
            _sum: { quantityKg: true },
          }),
        ]);
        const oh = new Map(onHand.map((r) => [`${r.currentSiteId}|${r.productId}`, Number(r._sum.weightKg ?? 0)]));
        const it = new Map(inTransit.map((r) => [`${r.destinationSiteId}|${r.productId}`, Number(r._sum.quantityKg ?? 0)]));

        const needs: Need[] = [];
        const report: Record<string, unknown>[] = [];
        for (const c of centres) {
          for (const p of products) {
            const key = `${c.id}|${p.id}`;
            const f = fc.get(key);
            const row = { siteId: c.id, siteCode: c.code, productId: p.id, productCode: p.code, forecastKg: f ?? null, onHandKg: oh.get(key) ?? 0, inTransitKg: it.get(key) ?? 0 };
            if (f === undefined) {
              report.push({ ...row, needKg: null, note: 'no forecast for this day' });
              continue;
            }
            const needKg = Math.max(0, f - row.onHandKg - row.inTransitKg);
            report.push({ ...row, needKg });
            if (needKg > 0) needs.push({ siteId: c.id, productId: p.id, lat: c.lat, lng: c.lng, needKg });
          }
        }

        const sources = await tx.site.findMany({ where: { active: true, type: { in: [...SOURCE_TYPES] } }, select: { id: true } });
        const available: Available[] = [];
        for (const s of sources) available.push(...(await this.orders.availableAt(tx, s.id)));
        const allocations = allocateFefo(needs, available);
        const short = shortfall(needs, allocations);

        // One order per (source, centre, product).
        const groups = new Map<string, typeof allocations>();
        for (const a of allocations) {
          const k = `${a.sourceSiteId}|${a.destinationSiteId}|${a.productId}`;
          groups.set(k, [...(groups.get(k) ?? []), a]);
        }
        const created = [];
        for (const group of groups.values()) {
          const first = group[0];
          const order = await tx.dispatchOrder.create({
            data: {
              code: await this.orders.newCode(tx, dayStart),
              sourceSiteId: first.sourceSiteId,
              destinationSiteId: first.destinationSiteId,
              productId: first.productId,
              quantityKg: group.reduce((s, a) => s + a.kg, 0),
              windowStart: istAt(date, PLAN_WINDOW.start),
              windowEnd: istAt(date, PLAN_WINDOW.end),
              origin: 'PLANNER',
              batches: { create: group.map((a) => ({ batchId: a.batchId, allocatedKg: a.kg })) },
            },
            include: { batches: { select: { batchId: true, allocatedKg: true } } },
          });
          created.push({ ...order, quantityKg: Number(order.quantityKg), batches: order.batches.map((b) => ({ batchId: b.batchId, allocatedKg: Number(b.allocatedKg) })) });
        }
        this.logger.log({ msg: 'planning run', date, by: user.id, orders: created.length, allocations: allocations.length });
        return {
          date,
          replacedDrafts: old.length,
          orders: created,
          needs: report.map((r) => ({ ...r, shortfallKg: r.needKg === null ? null : short.get(`${r.siteId}|${r.productId}`) ?? 0 })),
        };
      },
      { timeout: 30_000 },
    );
  }

  /**
   * POST /planning/routes: APPROVED orders loading at `depotSiteId` that day → ML route
   * optimiser (INITIAL) → one PLANNED trip per used vehicle with stops and route_plans v1.
   */
  async buildRoutes(user: AuthUser, date: string, depotSiteId: string) {
    const depot = await this.prisma.site.findUnique({ where: { id: depotSiteId } });
    if (!depot?.active) throw new AppError('UNKNOWN_SITE', 'Depot site not found', HttpStatus.UNPROCESSABLE_ENTITY);
    const orders = await this.prisma.dispatchOrder.findMany({
      where: { status: 'APPROVED', sourceSiteId: depotSiteId, windowStart: { gte: istAt(date), lt: istAt(date, '24:00') } },
      include: { destinationSite: true, batches: { include: { batch: { select: { remainingShelfLifeH: true } } } } },
    });
    if (!orders.length) throw new AppError('NO_APPROVED_ORDERS', 'No approved orders load at this depot on that day', HttpStatus.UNPROCESSABLE_ENTITY);

    let vehicles = await this.prisma.vehicle.findMany({ where: { status: 'AVAILABLE', homeSiteId: depotSiteId } });
    if (!vehicles.length) vehicles = await this.prisma.vehicle.findMany({ where: { status: 'AVAILABLE' } });
    if (!vehicles.length) throw new AppError('NO_VEHICLES', 'No available vehicles', HttpStatus.CONFLICT);

    const departAt = new Date(Math.max(Date.now(), istAt(date, PLAN_WINDOW.start).getTime()));
    const body = {
      mode: 'INITIAL',
      depot: { lat: depot.lat, lng: depot.lng },
      departAt: departAt.toISOString(),
      vehicles: vehicles.map((v) => ({ id: v.id, capacityKg: Number(v.capacityKg) })),
      stops: orders.map((o) => {
        const shelf = o.batches.map((b) => b.batch.remainingShelfLifeH).filter((h): h is Prisma.Decimal => h !== null).map(Number);
        return {
          id: o.id,
          lat: o.destinationSite.lat,
          lng: o.destinationSite.lng,
          demandKg: Number(o.quantityKg),
          windowStart: o.windowStart.toISOString(),
          windowEnd: o.windowEnd.toISOString(),
          serviceMin: 20,
          ...(shelf.length ? { shelfLifeH: Math.max(0, Math.min(...shelf)) } : {}),
        };
      }),
    };

    let plan: MlOptimize;
    try {
      plan = await this.ml.post<MlOptimize>('/v1/routes/optimize', body, ML_TIMEOUT_MS);
    } catch (e) {
      const err = e as MlCallError;
      throw new AppError('ROUTING_UNAVAILABLE', `Route optimiser failed: ${err.code}`, HttpStatus.SERVICE_UNAVAILABLE, err.details);
    }

    const byId = new Map(orders.map((o) => [o.id, o]));
    const trips = await this.prisma.$transaction(
      async (tx) => {
        const out = [];
        for (const route of plan.routes.filter((r) => r.stops.length)) {
          const code = await nextCode(tx, `TRP-${ymd(date)}-`, async (prefix) =>
            (await tx.trip.findFirst({ where: { code: { startsWith: prefix } }, orderBy: { code: 'desc' }, select: { code: true } }))?.code ?? null,
          );
          const trip = await tx.trip.create({
            data: { code, vehicleId: route.vehicleId, depotSiteId, plannedStart: departAt, distanceKm: route.distanceKm, currentRouteVersion: 1 },
          });
          const pickup = await tx.tripStop.create({
            data: { tripId: trip.id, seq: 1, routeVersion: 1, type: 'PICKUP', siteId: depotSiteId, lat: depot.lat, lng: depot.lng, eta: departAt },
          });
          const planStops: Record<string, unknown>[] = [{ stopId: pickup.id, seq: 1, type: 'PICKUP', siteId: depotSiteId, eta: departAt.toISOString() }];
          for (const [i, s] of route.stops.entries()) {
            const o = byId.get(s.id);
            if (!o) continue;
            const stop = await tx.tripStop.create({
              data: {
                tripId: trip.id, seq: i + 2, routeVersion: 1, type: 'DROP', siteId: o.destinationSiteId, orderId: o.id,
                lat: o.destinationSite.lat, lng: o.destinationSite.lng, windowStart: o.windowStart, windowEnd: o.windowEnd, eta: new Date(s.eta),
              },
            });
            planStops.push({ stopId: stop.id, seq: i + 2, type: 'DROP', siteId: o.destinationSiteId, orderId: o.id, eta: s.eta, lateMin: s.lateMin });
            await tx.dispatchOrder.update({ where: { id: o.id }, data: { status: 'PLANNED' } });
          }
          await tx.routePlan.create({
            data: { tripId: trip.id, version: 1, reason: 'INITIAL', stops: planStops as Prisma.InputJsonValue, fitness: route.distanceKm, status: 'ACCEPTED', respondedAt: new Date() },
          });
          out.push({ ...trip, distanceKm: route.distanceKm, loadKg: route.loadKg, stops: planStops });
        }
        return out;
      },
      { timeout: 30_000 },
    );

    for (const t of trips) this.realtime.toManagers('trip.updated', { tripId: t.id, status: t.status, code: t.code });
    await this.events.publish('order-transactions', depotSiteId, { type: 'ROUTES_BUILT', date, trips: trips.map((t) => t.id), by: user.id });
    return {
      date,
      depotSiteId,
      trips,
      optimiser: { feasible: plan.feasible, violations: plan.violations, distanceKm: plan.distanceKm, travelProvider: plan.travelProvider, latencyMs: plan.latencyMs },
    };
  }
}
