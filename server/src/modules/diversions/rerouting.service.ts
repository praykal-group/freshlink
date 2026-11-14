import { Inject, Injectable, Logger, Optional } from '@nestjs/common';
import { Prisma, type RouteReason, type StopType, type TripStop } from '@prisma/client';
import type { Queue } from 'bullmq';
import { minutesToMs } from '../../common/time-scale';
import { MlCallError, MlClient } from '../../infra/ml/ml-client.service';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { ALERTS_QUEUE } from '../../infra/queue/queues';
import { cumulativeEtaH, roadKm } from '../incidents/incident-rules';
import { NotificationsService } from '../notifications/notifications.service';
import { RealtimeService } from '../realtime/realtime.service';
import { RemoteConfigService } from '../remote-config/remote-config.service';

export const ROUTE_RESPONSE_JOB = 'route-response';
/** REPLAN must answer within 10 s (ML-04); the GA itself stops at 8 s. */
const ML_TIMEOUT_MS = 10_000;

export interface NewStop {
  key: string;
  type: StopType;
  siteId?: string | null;
  buyerId?: string | null;
  orderId?: string | null;
  lat: number;
  lng: number;
  demandKg: number;
  serviceMin?: number;
  shelfLifeH?: number;
  windowStart?: Date | null;
  windowEnd?: Date | null;
}

export interface ProposeInput {
  tripId: string;
  reason: RouteReason;
  /** Truck position now (REPLAN start). */
  start: { lat: number; lng: number };
  /** Stops that must open the new route, in this order (diversion / handover / rescue pickup). */
  first: NewStop[];
  /** Other stops the optimiser may order freely. */
  others: NewStop[];
}

export interface ProposeResult {
  tripId: string;
  version: number;
  reason: RouteReason;
  provider: 'ML' | 'FALLBACK';
  fallbackReason?: string;
  distanceKm: number;
  stops: { stopId: string; seq: number; type: StopType; eta: string; buyerId?: string | null; orderId?: string | null; siteId?: string | null }[];
}

interface MlRoute {
  routes: { vehicleId: string; stops: { id: string; eta: string; lateMin: number }[]; distanceKm: number }[];
  feasible: boolean;
}

/**
 * Builds a new route version for a running trip (SYN-06, W-1/W-2): ML REPLAN from the truck's
 * position with the new stop(s) as a fixed prefix, stored as a PROPOSED route plan + its stops, and
 * sent to the driver (`route.proposed`, push). The trip switches to it when the driver accepts
 * (TripsService.respondRoute). If the driver does not answer within `ackMinutes`, managers are told.
 * When the ML service is down the stops keep a simple order with indicative ETAs (logged).
 */
@Injectable()
export class ReroutingService {
  private readonly logger = new Logger(ReroutingService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly ml: MlClient,
    private readonly realtime: RealtimeService,
    private readonly notifications: NotificationsService,
    private readonly config: RemoteConfigService,
    @Optional() @Inject(ALERTS_QUEUE) private readonly queue?: Queue,
  ) {}

  /** Pending drop stops of the trip's current route (what is still to be delivered). */
  async pendingStops(tripId: string): Promise<(TripStop & { order: { quantityKg: Prisma.Decimal; batches: { batchId: string }[] } | null })[]> {
    const trip = await this.prisma.trip.findUniqueOrThrow({ where: { id: tripId }, select: { currentRouteVersion: true } });
    return this.prisma.tripStop.findMany({
      where: { tripId, routeVersion: trip.currentRouteVersion, status: { in: ['PENDING', 'ARRIVED'] }, type: { notIn: ['PICKUP', 'RESCUE_PICKUP'] } },
      include: { order: { select: { quantityKg: true, batches: { select: { batchId: true } } } } },
      orderBy: { seq: 'asc' },
    });
  }

  /** A pending stop carried into a new route version. */
  static carry(s: TripStop & { order: { quantityKg: Prisma.Decimal } | null }, keyPrefix = 'keep'): NewStop {
    return {
      key: `${keyPrefix}-${s.id}`,
      type: s.type,
      siteId: s.siteId,
      buyerId: s.buyerId,
      orderId: s.orderId,
      lat: s.lat,
      lng: s.lng,
      demandKg: s.order ? Number(s.order.quantityKg) : 0,
      windowStart: s.windowStart,
      windowEnd: s.windowEnd,
    };
  }

  async propose(input: ProposeInput): Promise<ProposeResult> {
    const trip = await this.prisma.trip.findUniqueOrThrow({ where: { id: input.tripId }, include: { vehicle: true, depotSite: true } });
    const all = [...input.first, ...input.others];
    const byKey = new Map(all.map((s) => [s.key, s]));

    // ── order + ETAs: ML REPLAN, else fixed prefix + previous order ──
    let order: string[] = all.map((s) => s.key);
    let etas = new Map<string, Date>();
    let provider: ProposeResult['provider'] = 'ML';
    let fallbackReason: string | undefined;
    let distanceKm = 0;
    const now = new Date();
    try {
      const body = {
        mode: 'REPLAN',
        depot: { lat: trip.depotSite.lat, lng: trip.depotSite.lng },
        departAt: now.toISOString(),
        vehicles: [{ id: trip.vehicleId, capacityKg: Number(trip.vehicle.capacityKg), start: input.start }],
        stops: all.map((s) => ({
          id: s.key,
          lat: s.lat,
          lng: s.lng,
          demandKg: s.demandKg,
          serviceMin: s.serviceMin ?? 20,
          ...(s.windowStart ? { windowStart: s.windowStart.toISOString() } : {}),
          ...(s.windowEnd ? { windowEnd: s.windowEnd.toISOString() } : {}),
          ...(s.shelfLifeH !== undefined ? { shelfLifeH: Math.max(0, s.shelfLifeH) } : {}),
        })),
        ...(input.first.length ? { fixedPrefix: { [trip.vehicleId]: input.first.map((s) => s.key) } } : {}),
      };
      const res = await this.ml.post<MlRoute>('/v1/routes/optimize', body, ML_TIMEOUT_MS);
      const route = res.routes.find((r) => r.vehicleId === trip.vehicleId);
      if (!route) throw new MlCallError(200, 'NO_ROUTE', 'optimiser returned no route for the vehicle');
      const seen = new Set(route.stops.map((s) => s.id));
      order = [...route.stops.map((s) => s.id), ...all.map((s) => s.key).filter((k) => !seen.has(k))];
      etas = new Map(route.stops.map((s) => [s.id, new Date(s.eta)]));
      distanceKm = route.distanceKm;
    } catch (e) {
      provider = 'FALLBACK';
      fallbackReason = e instanceof MlCallError ? `${e.code}: ${e.message}` : (e as Error).message;
      this.logger.warn({ msg: 'route optimiser unavailable, keeping a simple order', tripId: trip.id, error: fallbackReason });
    }
    if (provider === 'FALLBACK' || etas.size < order.length) {
      const pts = order.map((k) => ({ id: k, lat: byKey.get(k)!.lat, lng: byKey.get(k)!.lng, serviceMin: byKey.get(k)!.serviceMin }));
      const hours = cumulativeEtaH(input.start, pts);
      for (const k of order) if (!etas.has(k)) etas.set(k, new Date(now.getTime() + (hours.get(k) ?? 0) * 3_600_000));
      if (provider === 'FALLBACK') {
        let prev = input.start;
        for (const p of pts) {
          distanceKm += roadKm(prev, p);
          prev = p;
        }
      }
    }

    const ackMinutes = await this.config.get('ackMinutes');
    const result = await this.prisma.$transaction(async (tx) => {
      // An older proposal that was never answered is replaced by this one.
      const stale = await tx.routePlan.findMany({ where: { tripId: trip.id, status: 'PROPOSED' }, select: { version: true } });
      if (stale.length) {
        await tx.routePlan.updateMany({ where: { tripId: trip.id, status: 'PROPOSED' }, data: { status: 'SUPERSEDED' } });
        await tx.tripStop.updateMany({ where: { tripId: trip.id, routeVersion: { in: stale.map((s) => s.version) }, status: 'PENDING' }, data: { status: 'CANCELLED' } });
      }
      const last = await tx.routePlan.findFirst({ where: { tripId: trip.id }, orderBy: { version: 'desc' }, select: { version: true } });
      const version = Math.max(last?.version ?? 0, trip.currentRouteVersion) + 1;
      const stops: ProposeResult['stops'] = [];
      for (const [i, key] of order.entries()) {
        const s = byKey.get(key)!;
        const eta = etas.get(key)!;
        const row = await tx.tripStop.create({
          data: {
            tripId: trip.id, seq: i + 1, routeVersion: version, type: s.type, siteId: s.siteId ?? null, buyerId: s.buyerId ?? null, orderId: s.orderId ?? null,
            lat: s.lat, lng: s.lng, windowStart: s.windowStart ?? null, windowEnd: s.windowEnd ?? null, eta,
          },
        });
        stops.push({ stopId: row.id, seq: i + 1, type: s.type, eta: eta.toISOString(), buyerId: row.buyerId, orderId: row.orderId, siteId: row.siteId });
      }
      await tx.routePlan.create({
        data: { tripId: trip.id, version, reason: input.reason, stops: stops as unknown as Prisma.InputJsonValue, fitness: distanceKm, status: 'PROPOSED' },
      });
      return { tripId: trip.id, version, reason: input.reason, provider, fallbackReason, distanceKm: Math.round(distanceKm * 10) / 10, stops };
    });

    const payload = { tripId: trip.id, version: result.version, reason: result.reason, stops: result.stops, distanceKm: result.distanceKm };
    this.realtime.toTrip(trip.id, 'route.proposed', payload);
    this.realtime.toManagers('route.proposed', payload);
    if (trip.driverId) {
      try {
        await this.notifications.toDriver(trip.driverId, {
          title: 'New route: accept to continue',
          body: `Trip ${trip.code}: a new route (v${result.version}, ${result.reason.toLowerCase()}) protects your cargo. Open the app and accept it.`,
          critical: true,
          event: 'route.proposed',
          data: { tripId: trip.id, version: String(result.version) },
        });
      } catch (e) {
        this.logger.error({ msg: 'route.proposed notification failed', tripId: trip.id, error: (e as Error).message });
      }
    }
    await this.queue
      ?.add(ROUTE_RESPONSE_JOB, { tripId: trip.id, version: result.version }, { jobId: `route-${trip.id}-${result.version}`, delay: minutesToMs(ackMinutes) })
      .catch((e: Error) => this.logger.error({ msg: 'route-response job not scheduled', error: e.message }));
    return result;
  }

  /** Job: the driver has not answered the proposal → managers by push, email and SMS. */
  async responseTimeout(tripId: string, version: number): Promise<boolean> {
    const plan = await this.prisma.routePlan.findUnique({ where: { tripId_version: { tripId, version } }, include: { trip: { select: { code: true } } } });
    if (!plan || plan.status !== 'PROPOSED') return false;
    await this.notifications.toManagers(
      {
        title: 'Driver has not answered a reroute',
        body: `Trip ${plan.trip.code}: route v${version} (${plan.reason.toLowerCase()}) is still waiting for the driver. Call the driver.`,
        critical: true,
        event: 'route.updated',
        data: { tripId, version: String(version) },
      },
      { withSms: true },
    );
    return true;
  }

  async cancelResponseJob(tripId: string, version: number) {
    await this.queue?.remove(`route-${tripId}-${version}`).catch(() => undefined);
  }
}
