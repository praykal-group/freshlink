import { HttpStatus, Inject, Injectable, Logger, OnModuleInit, Optional } from '@nestjs/common';
import { type Grade, type Incident, type IncidentAction, type IncidentKind, Prisma, type StopType } from '@prisma/client';
import type { Queue } from 'bullmq';
import type { AuthUser } from '../../common/auth/auth-user';
import { AppError } from '../../common/errors/app-error';
import { afterCursor, toPage } from '../../common/pagination';
import { currentTimeScale, minutesToMs } from '../../common/time-scale';
import { EventBus } from '../../infra/events/event-bus.service';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { ALERTS_QUEUE } from '../../infra/queue/queues';
import { AlertsService } from '../alerts/alerts.service';
import { GRADE_RANK, type RankedBuyer, type RankResult, rankBuyers } from '../buyers/buyer-rules';
import { toBuyerIn } from '../buyers/buyers.service';
import { OffersService, offerView } from '../diversions/offers.service';
import { type RescueCandidateIn, type RescueRanked, rankRescue } from '../diversions/rescue-rules';
import { ReroutingService } from '../diversions/rerouting.service';
import { RealtimeService } from '../realtime/realtime.service';
import { RemoteConfigService } from '../remote-config/remote-config.service';
import { ShelfLifeService } from '../shelf-life/shelf-life.service';
import { DeviceContextService } from '../telemetry/device-context.service';
import { TelemetryService } from '../telemetry/telemetry.service';
import { TraceService } from '../trace/trace.service';
import type { IncidentActionDto, ListIncidentsQuery, ResolveIncidentDto } from './dto/incident.dto';
import { atSpoilageRisk, classify, cumulativeEtaH, type DecisionEntry, delayInfeasible, entry, tempSlopePer10Min, type TriggerSource } from './incident-rules';

export const DRIVER_FIX_RECHECK_JOB = 'driver-fix-recheck';
/** W-2: re-evaluate a DRIVER_FIX after 15 min (config minutes, time-scaled in tests). */
const DRIVER_FIX_MINUTES = 15;
/** Window for the temperature slope of the classifier. */
const SLOPE_WINDOW_MIN = 30;
/** A driver delay report without a duration counts as this many minutes. */
const DEFAULT_DELAY_MIN = 30;
const ACTIVE = ['OPEN', 'ACTION_IN_PROGRESS'] as const;

export interface Trigger {
  tripId: string;
  source: TriggerSource;
  alertId?: string | null;
  eventType?: string;
  eventId?: string;
  batchId?: string;
  details?: Record<string, unknown>;
}

interface CargoBatch {
  batchId: string;
  code: string;
  productId: string;
  productName: string;
  grade: Grade | null;
  weightKg: number;
  remainingShelfLifeH: number;
  safeMin: number;
  safeMax: number;
}

interface Cargo {
  tripId: string;
  code: string;
  vehicleId: string;
  driverId: string | null;
  batches: CargoBatch[];
  kg: number;
  minShelfH: number;
  worstGrade: Grade | null;
  position: { lat: number; lng: number };
  positionSource: 'POD_GPS' | 'DEPOT';
}

const summarise = (r: RankResult) => ({
  eligible: r.eligible.map((e) => ({ buyerId: e.buyer.id, name: e.buyer.name, type: e.buyer.type, discountPct: e.buyer.discountPct, etaH: round(e.etaH), distanceKm: round(e.distanceKm) })),
  excluded: r.excluded,
});
const round = (v: number) => Math.round(v * 100) / 100;

/**
 * Incident engine (W-2, Section 6.5). Triggers: critical temperature alerts and driver incident
 * reports (Kafka `alerts`, worker), the spoilage decision gate (every shelf-life estimate) and the
 * DRIVER_FIX re-check job. One active incident per trip; every step goes to `decision_log`.
 *
 *   TEMP_DRIFT      → DRIVER_FIX, re-check in 15 min → recovered: RESOLVED, else SPOILAGE_RISK
 *   REEFER_FAILURE  → nearest reachable cold storage (offer) → rescue truck → buyer (offer) → MANUAL
 *   SPOILAGE_RISK   → buyer offers (W-1) → MANUAL
 *   DELAY           → still feasible: REPLAN same stops; else buyer offers
 *   BREAKDOWN       → rescue truck → MANUAL (the truck cannot drive to a buyer)
 */
@Injectable()
export class IncidentsService implements OnModuleInit {
  private readonly logger = new Logger(IncidentsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly alerts: AlertsService,
    private readonly realtime: RealtimeService,
    private readonly config: RemoteConfigService,
    private readonly events: EventBus,
    private readonly telemetry: TelemetryService,
    private readonly context: DeviceContextService,
    private readonly shelfLife: ShelfLifeService,
    private readonly offers: OffersService,
    private readonly rerouting: ReroutingService,
    private readonly trace: TraceService,
    @Optional() @Inject(ALERTS_QUEUE) private readonly queue?: Queue,
  ) {}

  onModuleInit() {
    this.shelfLife.onEstimate(async (batchId, remainingH) => {
      await this.spoilageGate(batchId, remainingH);
    });
  }

  // ───────────── triggers ─────────────

  /** Spoilage decision gate (Section 1.1 step 6): runs after every shelf-life estimate. */
  async spoilageGate(batchId: string, remainingShelfLifeH: number): Promise<Incident | null> {
    const onTrip = await this.prisma.tripBatch.findFirst({ where: { batchId, unloadedAt: null, trip: { status: 'IN_PROGRESS' } }, include: { trip: true } });
    if (!onTrip) return null;
    const trip = onTrip.trip;
    if (await this.prisma.incident.count({ where: { tripId: trip.id, status: { in: [...ACTIVE] } } })) return null; // already being handled
    const pending = { tripId: trip.id, routeVersion: trip.currentRouteVersion, status: { in: ['PENDING' as const, 'ARRIVED' as const] }, eta: { not: null } };
    const stop =
      (await this.prisma.tripStop.findFirst({ where: { ...pending, order: { batches: { some: { batchId } } } }, orderBy: { seq: 'asc' } })) ??
      (await this.prisma.tripStop.findFirst({ where: { ...pending, type: { in: ['DIVERSION_DROP', 'COLD_STORAGE_DROP', 'RESCUE_DROP'] } }, orderBy: { seq: 'asc' } }));
    if (!stop?.eta) return null;
    const remainingEtaH = Math.max(0, (stop.eta.getTime() - Date.now()) / 3_600_000);
    const marginH = await this.config.get('safetyMarginH');
    if (!atSpoilageRisk(remainingShelfLifeH, remainingEtaH, marginH)) return null;
    return this.handleTrigger({ tripId: trip.id, source: 'SPOILAGE_GATE', batchId, details: { remainingShelfLifeH: round(remainingShelfLifeH), remainingEtaH: round(remainingEtaH), safetyMarginH: marginH, stopId: stop.id } });
  }

  async handleTrigger(t: Trigger): Promise<Incident | null> {
    const trip = await this.prisma.trip.findUnique({ where: { id: t.tripId } });
    if (!trip || trip.status !== 'IN_PROGRESS') return null;
    const reading = await this.telemetry.lastReading(trip.vehicleId);
    let slope: number | null = null;
    if (t.source === 'TEMP_ALERT') {
      const now = Date.now();
      const temps = await this.telemetry.vehicleTemps(trip.vehicleId, new Date(now - minutesToMs(SLOPE_WINDOW_MIN)), new Date(now)).catch(() => []);
      // Slope per 10 config minutes: under TELEMETRY_TIME_SCALE (tests) one real second is `scale` seconds.
      const scale = currentTimeScale();
      slope = tempSlopePer10Min(temps.map((p) => ({ at: p.at * scale, tempC: p.tempC })));
    }
    const driftSlopeMax = await this.config.get('driftSlopeMax');
    const c = classify({ source: t.source, reportedType: t.eventType, reeferOn: reading?.reeferOn ?? null, slopePer10Min: slope, driftSlopeMax });
    if (!c) return null;
    const inputs = {
      source: t.source, alertId: t.alertId ?? null, eventType: t.eventType ?? null, eventId: t.eventId ?? null, batchId: t.batchId ?? null,
      reeferOn: reading?.reeferOn ?? null, tempC: reading?.tempC ?? null, readingAt: reading?.ts ?? null, slopePer10Min: slope === null ? null : round(slope), driftSlopeMax,
      ...(t.details ?? {}),
    };

    const { incident, created } = await this.prisma.$transaction(async (tx) => {
      // One active incident per trip, even with triggers arriving from the API and the worker at once.
      await tx.$queryRaw`SELECT 1 FROM (SELECT pg_advisory_xact_lock(hashtext(${trip.id}))) AS l`;
      const active = await tx.incident.findFirst({ where: { tripId: trip.id, status: { in: [...ACTIVE] } }, orderBy: { createdAt: 'desc' } });
      if (active) return { incident: active, created: false };
      const inc = await tx.incident.create({
        data: { tripId: trip.id, alertId: t.alertId ?? null, kind: c.kind, decisionLog: [entry('CLASSIFIED', c.reason, { inputs: { ...inputs, kind: c.kind } })] as unknown as Prisma.InputJsonValue },
      });
      return { incident: inc, created: true };
    });

    if (!created) {
      const worse = c.kind === 'REEFER_FAILURE' || c.kind === 'SPOILAGE_RISK';
      if (incident.kind === 'TEMP_DRIFT' && incident.decidedAction === 'DRIVER_FIX' && worse) {
        await this.log(incident.id, entry('ESCALATED', `${c.kind} while the driver fix was running: ${c.reason}`, { inputs }));
        await this.queue?.remove(`dfr-${incident.id}`).catch(() => undefined);
        await this.prisma.incident.update({ where: { id: incident.id }, data: { kind: c.kind, status: 'OPEN' } });
        return this.decide(incident.id);
      }
      await this.log(incident.id, entry('TRIGGER_NOTED', `incident already active (${incident.kind}); new trigger classified ${c.kind}: ${c.reason}`, { inputs }));
      return incident;
    }
    this.emit(incident);
    await this.events.publish('alerts', incident.id, { type: 'INCIDENT_OPENED', incidentId: incident.id, tripId: trip.id, kind: incident.kind });
    return this.decide(incident.id);
  }

  // ───────────── decisions ─────────────

  async decide(id: string): Promise<Incident> {
    const inc = await this.prisma.incident.findUniqueOrThrow({ where: { id } });
    if (!ACTIVE.includes(inc.status as (typeof ACTIVE)[number])) return inc;
    switch (inc.kind) {
      case 'TEMP_DRIFT':
        return this.driverFix(inc);
      case 'DELAY':
        return this.delay(inc);
      default:
        return this.nextStep(inc);
    }
  }

  private async driverFix(inc: Incident): Promise<Incident> {
    const trip = await this.prisma.trip.findUniqueOrThrow({ where: { id: inc.tripId } });
    const alert = await this.alerts.raise({
      type: 'DRIVER_FIX',
      severity: 'WARNING',
      tripId: trip.id,
      vehicleId: trip.vehicleId,
      message: `Temperature drifting on trip ${trip.code}: check the door seals, the reefer setpoint and that the airflow is not blocked. Re-checked in ${DRIVER_FIX_MINUTES} min.`,
      data: { incidentId: inc.id },
      notifyDriver: true,
    });
    await this.queue
      ?.add(DRIVER_FIX_RECHECK_JOB, { incidentId: inc.id }, { jobId: `dfr-${inc.id}`, delay: minutesToMs(DRIVER_FIX_MINUTES) })
      .catch((e: Error) => this.logger.error({ msg: 'driver-fix re-check not scheduled', incidentId: inc.id, error: e.message }));
    return this.setAction(inc.id, 'DRIVER_FIX', entry('DRIVER_FIX', 'reefer running and the drift is slow: driver instructed to fix', { chosen: { alertId: alert.id, recheckInMin: DRIVER_FIX_MINUTES } }));
  }

  /** Job: 15 min after DRIVER_FIX. Back within limits → RESOLVED; otherwise → SPOILAGE_RISK. */
  async recheckDriverFix(incidentId: string): Promise<'RECOVERED' | 'ESCALATED' | 'SKIPPED'> {
    const inc = await this.prisma.incident.findUnique({ where: { id: incidentId } });
    if (!inc || inc.status !== 'ACTION_IN_PROGRESS' || inc.decidedAction !== 'DRIVER_FIX') return 'SKIPPED';
    const trip = await this.prisma.trip.findUniqueOrThrow({ where: { id: inc.tripId } });
    const [reading, cargo] = await Promise.all([this.telemetry.lastReading(trip.vehicleId), this.context.tripCargo(trip.id)]);
    const limits = cargo?.limits ?? null;
    const fresh = !!reading && Date.now() - Date.parse(reading.receivedAt) <= Math.max(minutesToMs(5), 60_000);
    const inRange = !!reading && !!limits && reading.tempC >= limits.tempMin && reading.tempC <= limits.tempMax;
    const inputs = { tempC: reading?.tempC ?? null, readingAt: reading?.ts ?? null, fresh, limits: limits && { min: limits.tempMin, max: limits.tempMax } };
    if (fresh && inRange) {
      await this.prisma.incident.update({ where: { id: inc.id }, data: { status: 'RESOLVED', resolvedAt: new Date() } });
      await this.log(inc.id, entry('DRIVER_FIX_RECOVERED', `temperature back to ${reading!.tempC} °C, within ${limits!.tempMin}–${limits!.tempMax} °C: no diversion needed`, { inputs }));
      const open = await this.prisma.alert.findMany({ where: { tripId: trip.id, type: { in: ['DRIVER_FIX', 'TEMP_EXCURSION'] }, status: { not: 'RESOLVED' } }, select: { id: true } });
      for (const a of open) await this.alerts.resolveBySystem(a.id);
      this.emit(await this.prisma.incident.findUniqueOrThrow({ where: { id: inc.id } }));
      return 'RECOVERED';
    }
    await this.log(inc.id, entry('DRIVER_FIX_FAILED', fresh ? 'temperature still outside the safe range' : 'no fresh reading from the pod', { inputs }));
    await this.prisma.incident.update({ where: { id: inc.id }, data: { kind: 'SPOILAGE_RISK', status: 'OPEN' } });
    await this.decide(inc.id);
    return 'ESCALATED';
  }

  private async delay(inc: Incident): Promise<Incident> {
    const cargo = await this.cargo(inc.tripId);
    const event = await this.prisma.tripEvent.findFirst({ where: { tripId: inc.tripId, type: { in: ['INCIDENT_DELAY', 'INCIDENT_ROADBLOCK'] } }, orderBy: { occurredAt: 'desc' } });
    const delayMin = Number((event?.payload as { delayMin?: unknown } | null)?.delayMin ?? DEFAULT_DELAY_MIN);
    const stops = await this.rerouting.pendingStops(inc.tripId);
    const etaByStop = cumulativeEtaH(cargo.position, stops.map((s) => ({ id: s.id, lat: s.lat, lng: s.lng })), (Number.isFinite(delayMin) ? delayMin : DEFAULT_DELAY_MIN) / 60);
    const stopOf = new Map<string, string>();
    for (const s of stops) for (const b of s.order?.batches ?? []) stopOf.set(b.batchId, s.id);
    const marginH = await this.config.get('safetyMarginH');
    const late = delayInfeasible(cargo.batches.map((b) => ({ batchId: b.batchId, stopId: stopOf.get(b.batchId) ?? null, remainingShelfLifeH: b.remainingShelfLifeH })), etaByStop, marginH);
    await this.log(inc.id, entry('DELAY_CHECK', late.length ? `${late.length} batch(es) would spoil before delivery` : 'delivery still feasible with the delay', {
      inputs: { delayMin, safetyMarginH: marginH, position: cargo.position, positionSource: cargo.positionSource, etaH: Object.fromEntries([...etaByStop].map(([k, v]) => [k, round(v)])) },
      candidates: { late },
    }));
    if (late.length) return this.nextStep(inc);
    const plan = await this.rerouting.propose({ tripId: inc.tripId, reason: 'DELAY', start: cargo.position, first: [], others: stops.map((s) => ReroutingService.carry(s)) });
    return this.setAction(inc.id, 'REPLAN', entry('ROUTE_PROPOSED', `same stops re-sequenced from the current position: route v${plan.version} sent to the driver (${plan.provider})`, { chosen: plan }));
  }

  /** The candidate chain for REEFER_FAILURE / SPOILAGE_RISK / BREAKDOWN / infeasible DELAY. */
  private async nextStep(inc: Incident): Promise<Incident> {
    const current = await this.prisma.incident.findUniqueOrThrow({ where: { id: inc.id } });
    if (!ACTIVE.includes(current.status as (typeof ACTIVE)[number])) return current;
    const cargo = await this.cargo(inc.tripId);
    if (!cargo.batches.length) return this.close(current.id, 'RESOLVED', entry('NO_CARGO', 'nothing left on board'));
    const marginH = await this.config.get('safetyMarginH');
    const offered = new Set((await this.prisma.diversionOffer.findMany({ where: { incidentId: inc.id }, select: { buyerId: true } })).map((o) => o.buyerId));
    const buyers = (await this.prisma.backupBuyer.findMany({ where: { active: true } })).map(toBuyerIn);
    const cargoIn = { productIds: [...new Set(cargo.batches.map((b) => b.productId))], grade: cargo.worstGrade, quantityKg: cargo.kg, remainingShelfLifeH: cargo.minShelfH, from: cargo.position, now: new Date(), safetyMarginH: marginH };
    const inputs = { cargoKg: cargo.kg, minShelfLifeH: round(cargo.minShelfH), grade: cargo.worstGrade ?? 'ungraded', position: cargo.position, positionSource: cargo.positionSource, safetyMarginH: marginH };

    if (current.kind === 'REEFER_FAILURE') {
      const cold = rankBuyers(buyers, cargoIn, { types: ['COLD_STORAGE'], excludeIds: offered, sort: 'NEAREST' });
      await this.log(inc.id, entry('COLD_STORAGE_SEARCH', cold.eligible.length ? `nearest reachable cold storage: ${cold.eligible[0].buyer.name}` : 'no reachable cold storage left', { inputs, candidates: summarise(cold) }));
      if (cold.eligible.length) return this.sendOffer(current, cold.eligible[0], cargo, 'DIVERT_COLD_STORAGE');
    }
    if (current.kind === 'REEFER_FAILURE' || current.kind === 'BREAKDOWN') {
      const tried = (current.decisionLog as unknown as DecisionEntry[]).some((e) => e.step === 'RESCUE_SEARCH');
      if (!tried) {
        const [rescue] = await this.findRescue(current, cargo, marginH);
        if (rescue) return this.applyRescue(current, cargo, rescue, null);
      }
    }
    if (current.kind === 'BREAKDOWN') return this.manual(current, 'the truck cannot move and no rescue truck is available');

    const any = rankBuyers(buyers, cargoIn, { excludeIds: offered, sort: 'DISCOUNT' });
    await this.log(inc.id, entry('BUYER_SEARCH', any.eligible.length ? `best buyer: ${any.eligible[0].buyer.name} (${any.eligible[0].buyer.discountPct}% discount)` : 'no eligible buyer left', { inputs, candidates: summarise(any) }));
    if (any.eligible.length) {
      const top = any.eligible[0];
      return this.sendOffer(current, top, cargo, top.buyer.type === 'COLD_STORAGE' ? 'DIVERT_COLD_STORAGE' : 'DIVERT_BUYER');
    }
    return this.manual(current, 'no eligible buyer, cold storage or rescue truck is left');
  }

  private async sendOffer(inc: Incident, ranked: RankedBuyer, cargo: Cargo, action: IncidentAction): Promise<Incident> {
    const products = [...new Set(cargo.batches.map((b) => b.productName))].join(', ');
    const { offer } = await this.offers.send({
      incidentId: inc.id,
      buyerId: ranked.buyer.id,
      batchIds: cargo.batches.map((b) => b.batchId),
      quantityKg: cargo.kg,
      cargoText: `${cargo.kg} kg ${products} (grade ${cargo.worstGrade ?? 'ungraded'})`,
      etaAt: ranked.arriveAt,
    });
    return this.setAction(inc.id, action, entry('OFFER_SENT', `offer sent to ${ranked.buyer.name} (${ranked.buyer.type}); waiting until ${offer.expiresAt.toISOString()}`, {
      chosen: { offerId: offer.id, buyerId: ranked.buyer.id, name: ranked.buyer.name, etaH: round(ranked.etaH), discountPct: ranked.buyer.discountPct, expiresAt: offer.expiresAt },
    }));
  }

  /** Public offer page answer. Throws 404 / 410 for unknown, expired or already answered tokens. */
  async respondOffer(token: string, accept: boolean) {
    const offer = await this.offers.claim(token, accept);
    const buyer = await this.prisma.backupBuyer.findUniqueOrThrow({ where: { id: offer.buyerId } });
    if (!accept) {
      await this.log(offer.incidentId, entry('OFFER_REJECTED', `${buyer.name} rejected the offer`, { chosen: { offerId: offer.id } }));
      await this.nextStep(await this.prisma.incident.findUniqueOrThrow({ where: { id: offer.incidentId } }));
      return offer;
    }
    await this.log(offer.incidentId, entry('OFFER_ACCEPTED', `${buyer.name} accepted the offer`, { chosen: { offerId: offer.id } }));
    await this.applyDiversion(offer.incidentId, buyer.id, offer.batchIds, null);
    return offer;
  }

  /** Job: the offer timed out → next candidate. */
  async expireOffer(offerId: string): Promise<boolean> {
    const offer = await this.offers.expire(offerId);
    if (!offer) return false;
    await this.log(offer.incidentId, entry('OFFER_EXPIRED', 'no answer before the offer expired', { chosen: { offerId } }));
    await this.nextStep(await this.prisma.incident.findUniqueOrThrow({ where: { id: offer.incidentId } }));
    return true;
  }

  /** Route changes only after the buyer accepted (W-1): batches DIVERTED + new route proposed. */
  private async applyDiversion(incidentId: string, buyerId: string, batchIds: string[], by: string | null): Promise<Incident> {
    const inc = await this.prisma.incident.findUniqueOrThrow({ where: { id: incidentId } });
    const buyer = await this.prisma.backupBuyer.findUniqueOrThrow({ where: { id: buyerId } });
    const cargo = await this.cargo(inc.tripId);
    const diverted = cargo.batches.filter((b) => batchIds.includes(b.batchId));
    const stopType: StopType = buyer.type === 'COLD_STORAGE' ? 'COLD_STORAGE_DROP' : 'DIVERSION_DROP';
    const action: IncidentAction = buyer.type === 'COLD_STORAGE' ? 'DIVERT_COLD_STORAGE' : 'DIVERT_BUYER';
    await this.prisma.$transaction(async (tx) => {
      for (const b of diverted) {
        await tx.batch.update({ where: { id: b.batchId }, data: { status: 'DIVERTED' } });
        await this.trace.append(tx, b.batchId, 'DIVERTED', { tripCode: cargo.code, buyer: buyer.name, buyerType: buyer.type, reason: inc.kind, incidentId: inc.id }, by);
      }
    });
    const ids = new Set(diverted.map((b) => b.batchId));
    const kept = (await this.rerouting.pendingStops(inc.tripId)).filter((s) => s.type !== 'DROP' || (s.order?.batches ?? []).some((b) => !ids.has(b.batchId) && cargo.batches.some((c) => c.batchId === b.batchId)));
    const plan = await this.rerouting.propose({
      tripId: inc.tripId,
      reason: 'DIVERSION',
      start: cargo.position,
      first: [{ key: 'divert', type: stopType, buyerId: buyer.id, lat: buyer.lat, lng: buyer.lng, demandKg: diverted.reduce((a, b) => a + b.weightKg, 0), serviceMin: 30, shelfLifeH: Math.min(...diverted.map((b) => b.remainingShelfLifeH)) }],
      others: kept.map((s) => ReroutingService.carry(s)),
    });
    return this.setAction(inc.id, action, entry('ROUTE_PROPOSED', `divert ${diverted.length} batch(es) to ${buyer.name}: route v${plan.version} sent to the driver (${plan.provider})`, { chosen: plan, by }));
  }

  /** Logs the search and returns every eligible truck, nearest first. */
  private async findRescue(inc: Incident, cargo: Cargo, marginH: number): Promise<RescueRanked[]> {
    const radiusKm = await this.config.get('rescueRadiusKm');
    const trips = await this.prisma.trip.findMany({
      where: { status: 'IN_PROGRESS', id: { not: inc.tripId } },
      include: { vehicle: true, batches: { where: { unloadedAt: null }, include: { batch: { include: { product: true } } } } },
    });
    const cands: RescueCandidateIn[] = await Promise.all(
      trips.map(async (t) => {
        const r = await this.telemetry.lastReading(t.vehicleId);
        return {
          tripId: t.id,
          code: t.code,
          vehicleId: t.vehicleId,
          reefer: { min: Number(t.vehicle.reeferMinTemp), max: Number(t.vehicle.reeferMaxTemp) },
          capacityKg: Number(t.vehicle.capacityKg),
          loadKg: t.batches.reduce((a, b) => a + Number(b.batch.weightKg), 0),
          cargoRanges: t.batches.map((b) => ({ min: Number(b.batch.product.safeTempMin), max: Number(b.batch.product.safeTempMax) })),
          position: r && r.lat !== null && r.lng !== null ? { lat: r.lat, lng: r.lng } : null,
        };
      }),
    );
    const ranked = rankRescue(cands, {
      failingTripId: inc.tripId,
      cargoRanges: cargo.batches.map((b) => ({ min: b.safeMin, max: b.safeMax })),
      cargoKg: cargo.kg,
      at: cargo.position,
      radiusKm,
      remainingShelfLifeH: cargo.minShelfH,
      safetyMarginH: marginH,
    });
    await this.log(inc.id, entry('RESCUE_SEARCH', ranked.eligible.length ? `nearest compatible truck: ${ranked.eligible[0].candidate.code}` : 'no compatible truck within range', {
      inputs: { radiusKm, cargoKg: cargo.kg, position: cargo.position, positionSource: cargo.positionSource },
      candidates: { eligible: ranked.eligible.map((e) => ({ tripId: e.candidate.tripId, code: e.candidate.code, distanceKm: round(e.distanceKm), etaH: round(e.etaH), setpoint: e.setpoint })), excluded: ranked.excluded },
    }));
    return ranked.eligible;
  }

  /** Two-trip replan: the failing truck hands over where it is; the rescue truck picks up there first. */
  private async applyRescue(inc: Incident, cargo: Cargo, rescue: RescueRanked, by: string | null): Promise<Incident> {
    const rescueTripId = rescue.candidate.tripId;
    const transferred = (await this.rerouting.pendingStops(inc.tripId)).filter((s) => s.type === 'DROP').map((s) => ReroutingService.carry(s, 'moved'));
    const own = (await this.rerouting.pendingStops(rescueTripId)).map((s) => ReroutingService.carry(s));
    const handover = { lat: cargo.position.lat, lng: cargo.position.lng };
    const failingPlan = await this.rerouting.propose({
      tripId: inc.tripId,
      reason: 'RESCUE',
      start: cargo.position,
      first: [{ key: 'handover', type: 'RESCUE_DROP', ...handover, demandKg: cargo.kg, serviceMin: 30 }],
      others: [],
    });
    const rescuePlan = await this.rerouting.propose({
      tripId: rescueTripId,
      reason: 'RESCUE',
      start: rescue.candidate.position!,
      first: [{ key: 'rescue-pickup', type: 'RESCUE_PICKUP', ...handover, demandKg: 0, serviceMin: 30 }],
      others: [...own, ...transferred],
    });
    await this.prisma.incident.update({ where: { id: inc.id }, data: { rescueTripId } });
    return this.setAction(inc.id, 'RESCUE_PICKUP', entry('RESCUE_PLANNED', `${rescue.candidate.code} takes over the cargo at the failing truck's position`, {
      chosen: { rescueTripId, rescueTripCode: rescue.candidate.code, distanceKm: round(rescue.distanceKm), etaH: round(rescue.etaH), setpoint: rescue.setpoint, failingRoute: failingPlan, rescueRoute: rescuePlan },
      by,
    }));
  }

  /** No candidates left → MANUAL + managers alerted (push, email, SMS). */
  private async manual(inc: Incident, reason: string): Promise<Incident> {
    const trip = await this.prisma.trip.findUniqueOrThrow({ where: { id: inc.tripId } });
    const alert = await this.alerts.raise({
      type: 'SPOILAGE_RISK',
      severity: 'CRITICAL',
      tripId: trip.id,
      vehicleId: trip.vehicleId,
      message: `Manual action needed on trip ${trip.code} (${inc.kind.replace(/_/g, ' ').toLowerCase()}): ${reason}`,
      data: { incidentId: inc.id },
      smsManagers: true,
    });
    await this.prisma.incident.update({ where: { id: inc.id }, data: { decidedAction: 'MANUAL', status: 'OPEN' } });
    await this.log(inc.id, entry('MANUAL', reason, { chosen: { alertId: alert.id } }));
    const updated = await this.prisma.incident.findUniqueOrThrow({ where: { id: inc.id } });
    this.emit(updated);
    return updated;
  }

  // ───────────── lifecycle hooks (trips / PoD) ─────────────

  /** Driver accepted a route version. A DELAY/manual REPLAN is done once accepted. */
  async onRouteAccepted(tripId: string, version: number, reason: string) {
    await this.rerouting.cancelResponseJob(tripId, version);
    const inc = await this.prisma.incident.findFirst({ where: { tripId, status: { in: [...ACTIVE] } }, orderBy: { createdAt: 'desc' } });
    if (!inc) return;
    await this.log(inc.id, entry('ROUTE_ACCEPTED', `driver accepted route v${version} (${reason})`));
    if (inc.decidedAction === 'REPLAN') await this.close(inc.id, 'RESOLVED', entry('RESOLVED', 'driver is on the re-planned route'));
  }

  async onRouteDeclined(tripId: string, version: number) {
    await this.rerouting.cancelResponseJob(tripId, version);
  }

  /** PoD finished a diversion / cold-storage / rescue drop. */
  async onDropCompleted(tripId: string, stopType: StopType) {
    if (!['DIVERSION_DROP', 'COLD_STORAGE_DROP', 'RESCUE_DROP'].includes(stopType)) return;
    const inc = await this.prisma.incident.findFirst({ where: { tripId, status: { in: [...ACTIVE] } }, orderBy: { createdAt: 'desc' } });
    if (!inc) return;
    const text = stopType === 'RESCUE_DROP' ? 'cargo handed over to the rescue truck' : `cargo delivered at the ${stopType === 'COLD_STORAGE_DROP' ? 'cold storage' : 'buyer'}`;
    await this.close(inc.id, 'RESOLVED', entry('RESOLVED', text));
  }

  /** The trip that takes over the cargo at a RESCUE_DROP of `tripId`. */
  async rescueTripFor(tripId: string): Promise<string | null> {
    const inc = await this.prisma.incident.findFirst({ where: { tripId, decidedAction: 'RESCUE_PICKUP', rescueTripId: { not: null } }, orderBy: { createdAt: 'desc' } });
    return inc?.rescueTripId ?? null;
  }

  // ───────────── manager API ─────────────

  async list(q: ListIncidentsQuery) {
    const limit = q.limit ?? 20;
    const rows = await this.prisma.incident.findMany({
      where: { AND: [q.status ? { status: q.status } : {}, q.tripId ? { tripId: q.tripId } : {}, afterCursor(q.cursor) as Prisma.IncidentWhereInput] },
      include: { trip: { select: { code: true, vehicleId: true } } },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
    });
    const page = toPage(rows, limit);
    return { items: page.items.map(({ decisionLog, ...i }) => ({ ...i, steps: (decisionLog as unknown as DecisionEntry[]).length })), nextCursor: page.nextCursor };
  }

  async detail(id: string) {
    const inc = await this.prisma.incident.findUnique({
      where: { id },
      include: { trip: { select: { code: true, vehicleId: true, driverId: true, status: true, currentRouteVersion: true } }, rescueTrip: { select: { code: true } }, offers: { include: { buyer: { select: { name: true, type: true } } }, orderBy: { createdAt: 'asc' } } },
    });
    if (!inc) throw new AppError('NOT_FOUND', 'Incident not found', HttpStatus.NOT_FOUND);
    return { ...inc, offers: inc.offers.map((o) => ({ ...offerView(o), buyer: o.buyer })) };
  }

  async offersFor(id: string) {
    return (await this.detail(id)).offers;
  }

  /** POST /incidents/:id/action (MANAGER override, Section 6.5 rule 5). */
  async action(user: AuthUser, id: string, dto: IncidentActionDto) {
    const inc = await this.prisma.incident.findUnique({ where: { id } });
    if (!inc) throw new AppError('NOT_FOUND', 'Incident not found', HttpStatus.NOT_FOUND);
    if (!ACTIVE.includes(inc.status as (typeof ACTIVE)[number])) throw new AppError('INCIDENT_CLOSED', `Incident is ${inc.status}`, HttpStatus.CONFLICT);
    const trip = await this.prisma.trip.findUniqueOrThrow({ where: { id: inc.tripId } });
    if (trip.status !== 'IN_PROGRESS' && dto.action !== 'MANUAL') throw new AppError('INVALID_TRIP_STATUS', `Trip is ${trip.status}`, HttpStatus.CONFLICT);

    const cancelled = await this.offers.cancelOpen(id);
    await this.queue?.remove(`dfr-${id}`).catch(() => undefined);
    await this.log(id, entry('MANUAL_OVERRIDE', dto.note ?? `manager chose ${dto.action}`, { inputs: { ...dto, cancelledOffers: cancelled }, by: user.id }));
    await this.prisma.incident.update({ where: { id }, data: { status: 'OPEN' } });

    switch (dto.action) {
      case 'DRIVER_FIX':
        await this.driverFix(inc);
        break;
      case 'DIVERT_BUYER':
      case 'DIVERT_COLD_STORAGE': {
        if (!dto.buyerId) throw new AppError('VALIDATION_FAILED', 'buyerId is required', HttpStatus.UNPROCESSABLE_ENTITY);
        const buyer = await this.prisma.backupBuyer.findUnique({ where: { id: dto.buyerId } });
        if (!buyer?.active) throw new AppError('UNKNOWN_BUYER', 'Buyer not found or inactive', HttpStatus.UNPROCESSABLE_ENTITY);
        if (dto.action === 'DIVERT_COLD_STORAGE' && buyer.type !== 'COLD_STORAGE') throw new AppError('NOT_COLD_STORAGE', 'This buyer is not a cold storage', HttpStatus.UNPROCESSABLE_ENTITY);
        const cargo = await this.cargo(inc.tripId);
        if (!cargo.batches.length) throw new AppError('NO_CARGO', 'Nothing on board', HttpStatus.CONFLICT);
        await this.offers.recordAccepted(id, buyer.id, cargo.batches.map((b) => b.batchId), cargo.kg);
        await this.applyDiversion(id, buyer.id, cargo.batches.map((b) => b.batchId), user.id);
        break;
      }
      case 'RESCUE_PICKUP': {
        if (!dto.rescueTripId) throw new AppError('VALIDATION_FAILED', 'rescueTripId is required', HttpStatus.UNPROCESSABLE_ENTITY);
        const cargo = await this.cargo(inc.tripId);
        const marginH = await this.config.get('safetyMarginH');
        const eligible = await this.findRescue(inc, cargo, marginH);
        const chosen = eligible.find((e) => e.candidate.tripId === dto.rescueTripId) ?? (await this.rescueRefused(inc.id, dto.rescueTripId));
        await this.applyRescue(inc, cargo, chosen, user.id);
        break;
      }
      case 'REPLAN': {
        const cargo = await this.cargo(inc.tripId);
        const stops = await this.rerouting.pendingStops(inc.tripId);
        const plan = await this.rerouting.propose({ tripId: inc.tripId, reason: 'MANUAL', start: cargo.position, first: [], others: stops.map((s) => ReroutingService.carry(s)) });
        await this.setAction(id, 'REPLAN', entry('ROUTE_PROPOSED', `manual re-plan: route v${plan.version} sent to the driver (${plan.provider})`, { chosen: plan, by: user.id }));
        break;
      }
      case 'MANUAL':
        await this.setAction(id, 'MANUAL', entry('MANUAL', 'handled by the manager outside the system', { by: user.id }));
        break;
    }
    return this.detail(id);
  }

  /** Manager closes the incident (RESOLVED, or FAILED when the cargo was lost). */
  async resolve(user: AuthUser, id: string, dto: ResolveIncidentDto) {
    const inc = await this.prisma.incident.findUnique({ where: { id } });
    if (!inc) throw new AppError('NOT_FOUND', 'Incident not found', HttpStatus.NOT_FOUND);
    if (!ACTIVE.includes(inc.status as (typeof ACTIVE)[number])) return this.detail(id);
    await this.offers.cancelOpen(id);
    await this.queue?.remove(`dfr-${id}`).catch(() => undefined);
    await this.close(id, dto.failed ? 'FAILED' : 'RESOLVED', entry(dto.failed ? 'FAILED' : 'RESOLVED', dto.note ?? 'closed by the manager', { by: user.id }));
    return this.detail(id);
  }

  // ───────────── helpers ─────────────

  /** The manager picked a truck that is not eligible: 422 with the reason from the search just logged. */
  private async rescueRefused(incidentId: string, rescueTripId: string): Promise<never> {
    const log = (await this.prisma.incident.findUniqueOrThrow({ where: { id: incidentId } })).decisionLog as unknown as DecisionEntry[];
    const search = [...log].reverse().find((e) => e.step === 'RESCUE_SEARCH');
    const excluded = (search?.candidates as { excluded?: { tripId: string; reason: string; detail?: string }[] } | undefined)?.excluded?.find((x) => x.tripId === rescueTripId);
    throw new AppError('RESCUE_NOT_POSSIBLE', excluded ? `That truck cannot rescue this cargo: ${excluded.reason}` : 'That trip is not an active truck that can rescue this cargo', HttpStatus.UNPROCESSABLE_ENTITY, {
      rescueTripId,
      reason: excluded?.reason ?? 'NOT_A_CANDIDATE',
      detail: excluded?.detail ?? null,
    });
  }

  private async cargo(tripId: string): Promise<Cargo> {
    const trip = await this.prisma.trip.findUniqueOrThrow({ where: { id: tripId }, include: { depotSite: true } });
    const rows = await this.prisma.tripBatch.findMany({ where: { tripId, unloadedAt: null }, include: { batch: { include: { product: true } } } });
    const batches: CargoBatch[] = rows.map(({ batch: b }) => ({
      batchId: b.id,
      code: b.code,
      productId: b.productId,
      productName: b.product.name,
      grade: b.currentGrade,
      weightKg: Number(b.weightKg),
      // No estimate yet: the product's base shelf life minus the batch age (logged as inputs).
      remainingShelfLifeH: b.remainingShelfLifeH !== null ? Number(b.remainingShelfLifeH) : Math.max(0, Number(b.product.baseShelfLifeH) - (Date.now() - b.caughtOrHarvestedAt.getTime()) / 3_600_000),
      safeMin: Number(b.product.safeTempMin),
      safeMax: Number(b.product.safeTempMax),
    }));
    const r = await this.telemetry.lastReading(trip.vehicleId);
    const pod = r && r.lat !== null && r.lng !== null ? { lat: r.lat, lng: r.lng } : null;
    const graded = batches.map((b) => b.grade);
    const worstGrade = !graded.length || graded.includes(null) ? null : (graded as Grade[]).reduce((w, g) => (GRADE_RANK[g] < GRADE_RANK[w] ? g : w));
    return {
      tripId,
      code: trip.code,
      vehicleId: trip.vehicleId,
      driverId: trip.driverId,
      batches,
      kg: Math.round(batches.reduce((a, b) => a + b.weightKg, 0) * 1000) / 1000,
      minShelfH: batches.length ? Math.min(...batches.map((b) => b.remainingShelfLifeH)) : 0,
      worstGrade,
      position: pod ?? { lat: trip.depotSite.lat, lng: trip.depotSite.lng },
      positionSource: pod ? 'POD_GPS' : 'DEPOT',
    };
  }

  private async setAction(id: string, action: IncidentAction, e: DecisionEntry): Promise<Incident> {
    await this.prisma.incident.update({ where: { id }, data: { decidedAction: action, status: action === 'MANUAL' ? 'OPEN' : 'ACTION_IN_PROGRESS' } });
    await this.log(id, e);
    const inc = await this.prisma.incident.findUniqueOrThrow({ where: { id } });
    this.emit(inc);
    return inc;
  }

  private async close(id: string, status: 'RESOLVED' | 'FAILED', e: DecisionEntry): Promise<Incident> {
    await this.prisma.incident.update({ where: { id }, data: { status, resolvedAt: new Date() } });
    await this.log(id, e);
    const inc = await this.prisma.incident.findUniqueOrThrow({ where: { id } });
    this.emit(inc);
    await this.events.publish('alerts', id, { type: 'INCIDENT_CLOSED', incidentId: id, tripId: inc.tripId, status });
    return inc;
  }

  /** Append-only decision log; a single SQL append, so concurrent steps never overwrite each other. */
  private async log(id: string, e: DecisionEntry) {
    await this.prisma.$executeRaw`UPDATE incidents SET decision_log = decision_log || ${JSON.stringify([e])}::jsonb, updated_at = now() WHERE id = ${id}::uuid`;
  }

  private emit(i: Incident) {
    const payload = { incidentId: i.id, tripId: i.tripId, kind: i.kind as IncidentKind, status: i.status, decidedAction: i.decidedAction };
    this.realtime.toManagers('incident.updated', payload);
    this.realtime.toTrip(i.tripId, 'incident.updated', payload);
  }
}
