import { HttpStatus, Injectable, Logger, Optional } from '@nestjs/common';
import { Prisma, type Trip, type TripEventType } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import type { AuthUser } from '../../common/auth/auth-user';
import { AppError } from '../../common/errors/app-error';
import { istAt } from '../../common/ist';
import { afterCursor, type PageQuery, toPage } from '../../common/pagination';
import { EventBus } from '../../infra/events/event-bus.service';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { AlertsService } from '../alerts/alerts.service';
import { FilesService } from '../files/files.service';
import { IncidentsService } from '../incidents/incidents.service';
import { RealtimeService } from '../realtime/realtime.service';
import { RemoteConfigService } from '../remote-config/remote-config.service';
import { SmsService } from '../sms/sms.service';
import { StorageService } from '../storage/storage.service';
import { TelemetryService } from '../telemetry/telemetry.service';
import { TraceService } from '../trace/trace.service';
import type { ArriveDto, ListTripsQuery, PreCheckDto, TripEventDto } from './dto/trip.dto';
import { allowedSetpoint, canDo, co2Kg, mapsLink, preCheckProblems, type TripAction } from './trip-rules';

type Tx = Prisma.TransactionClient;
const ACTIVE_FOR_DRIVER = ['ASSIGNED', 'PRE_CHECK_DONE', 'IN_PROGRESS'] as const;
const STOP_DONE = ['COMPLETED', 'SKIPPED', 'CANCELLED'];

function fail(code: string, message: string, status: HttpStatus, details?: Record<string, unknown>): never {
  throw new AppError(code, message, status, details);
}

export const tripView = (t: Trip) => ({ ...t, distanceKm: t.distanceKm === null ? null : Number(t.distanceKm), co2Kg: t.co2Kg === null ? null : Number(t.co2Kg) });

@Injectable()
export class TripsService {
  private readonly logger = new Logger(TripsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly trace: TraceService,
    private readonly storage: StorageService,
    private readonly files: FilesService,
    private readonly sms: SmsService,
    private readonly config: RemoteConfigService,
    private readonly realtime: RealtimeService,
    private readonly events: EventBus,
    private readonly alerts: AlertsService,
    @Optional() private readonly telemetry?: TelemetryService,
    @Optional() private readonly incidents?: IncidentsService,
  ) {}

  // ───────────── access ─────────────

  /** Loads a trip; drivers only their own (Section 6.3). */
  async loadForUser(user: AuthUser, id: string): Promise<Trip> {
    const trip = await this.prisma.trip.findUnique({ where: { id } });
    if (!trip) fail('NOT_FOUND', 'Trip not found', HttpStatus.NOT_FOUND);
    if (user.role === 'DRIVER' && trip.driverId !== user.id) fail('FORBIDDEN_TRIP', 'Trip belongs to another driver', HttpStatus.FORBIDDEN);
    return trip;
  }

  assertCan(trip: Trip, action: TripAction) {
    if (!canDo(trip.status, action)) fail('INVALID_TRIP_STATUS', `Cannot ${action} a trip that is ${trip.status}`, HttpStatus.CONFLICT, { status: trip.status });
  }

  private notify(trip: Pick<Trip, 'id' | 'driverId'>, payload: Record<string, unknown>) {
    this.realtime.toTrip(trip.id, 'trip.updated', payload);
    this.realtime.toManagers('trip.updated', payload);
    if (trip.driverId) this.realtime.toUser(trip.driverId, 'trip.updated', payload);
  }

  // ───────────── read ─────────────

  async list(q: ListTripsQuery) {
    const limit = q.limit ?? 20;
    const rows = await this.prisma.trip.findMany({
      where: {
        AND: [
          q.status ? { status: q.status } : {},
          q.date ? { plannedStart: { gte: istAt(q.date), lt: istAt(q.date, '24:00') } } : {},
          afterCursor(q.cursor) as Prisma.TripWhereInput,
        ],
      },
      include: { vehicle: { select: { regNo: true } }, driver: { select: { name: true } } },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
    });
    const page = toPage(rows, limit);
    return { items: page.items.map(tripView), nextCursor: page.nextCursor };
  }

  async detail(user: AuthUser, id: string) {
    const trip = await this.loadForUser(user, id);
    const [stops, batches, vehicle, driver] = await Promise.all([
      this.prisma.tripStop.findMany({
        where: { tripId: id, routeVersion: trip.currentRouteVersion },
        include: { site: { select: { code: true, name: true } } },
        orderBy: { seq: 'asc' },
      }),
      this.prisma.tripBatch.findMany({ where: { tripId: id }, include: { batch: { select: { code: true, productId: true, weightKg: true, status: true, currentGrade: true } } } }),
      this.prisma.vehicle.findUnique({ where: { id: trip.vehicleId }, select: { id: true, regNo: true, capacityKg: true } }),
      trip.driverId ? this.prisma.user.findUnique({ where: { id: trip.driverId }, select: { id: true, name: true, phone: true } }) : null,
    ]);
    return {
      ...tripView(trip),
      vehicle: vehicle && { ...vehicle, capacityKg: Number(vehicle.capacityKg) },
      driver,
      stops,
      batches: batches.map((b) => ({ batchId: b.batchId, loadedAt: b.loadedAt, unloadedAt: b.unloadedAt, ...b.batch, weightKg: Number(b.batch.weightKg) })),
    };
  }

  async currentForDriver(user: AuthUser) {
    const trip = await this.prisma.trip.findFirst({
      where: { driverId: user.id, status: { in: [...ACTIVE_FOR_DRIVER] } },
      orderBy: [{ status: 'desc' }, { plannedStart: 'asc' }], // IN_PROGRESS sorts first
    });
    return trip ? this.detail(user, trip.id) : null;
  }

  async historyForDriver(user: AuthUser, q: PageQuery) {
    const limit = q.limit ?? 20;
    const rows = await this.prisma.trip.findMany({
      where: { AND: [{ driverId: user.id }, afterCursor(q.cursor) as Prisma.TripWhereInput] },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
    });
    const page = toPage(rows, limit);
    const pods = await this.prisma.proofOfDelivery.groupBy({ by: ['tripStopId'], where: { tripStop: { tripId: { in: page.items.map((t) => t.id) } } }, _count: true });
    const podStops = new Set(pods.map((p) => p.tripStopId));
    return { items: page.items.map((t) => ({ ...tripView(t), podStops: podStops.size })), nextCursor: page.nextCursor };
  }

  async route(user: AuthUser, id: string) {
    const trip = await this.loadForUser(user, id);
    const [accepted, pending] = await Promise.all([
      this.prisma.routePlan.findFirst({ where: { tripId: id, version: trip.currentRouteVersion } }),
      this.prisma.routePlan.findFirst({ where: { tripId: id, status: 'PROPOSED' }, orderBy: { version: 'desc' } }),
    ]);
    return { currentVersion: trip.currentRouteVersion, accepted, pending };
  }

  async cargoStatus(user: AuthUser, id: string) {
    const trip = await this.loadForUser(user, id);
    const onBoard = await this.prisma.tripBatch.findMany({
      where: { tripId: id, unloadedAt: null },
      include: { batch: { include: { product: { select: { code: true, name: true, nameHi: true, nameMr: true, safeTempMin: true, safeTempMax: true } } } } },
    });
    return {
      tripId: id,
      // Latest pod reading (DA-FR-05); null before the first packet or when Redis is unavailable.
      telemetry: (await this.telemetry?.lastReading(trip.vehicleId)) ?? null,
      batches: onBoard.map(({ batch: b }) => ({
        batchId: b.id,
        code: b.code,
        product: { ...b.product, safeTempMin: Number(b.product.safeTempMin), safeTempMax: Number(b.product.safeTempMax) },
        grade: b.currentGrade,
        weightKg: Number(b.weightKg),
        remainingShelfLifeH: b.remainingShelfLifeH === null ? null : Number(b.remainingShelfLifeH),
        shelfLifeUpdatedAt: b.shelfLifeUpdatedAt,
      })),
    };
  }

  // ───────────── manager: assign ─────────────

  async assign(user: AuthUser, id: string, driverId: string, vehicleId: string) {
    const trip = await this.loadForUser(user, id);
    this.assertCan(trip, 'assign');
    const [driver, vehicle] = await Promise.all([
      this.prisma.user.findUnique({ where: { id: driverId } }),
      this.prisma.vehicle.findUnique({ where: { id: vehicleId } }),
    ]);
    if (!driver || driver.role !== 'DRIVER' || driver.status !== 'ACTIVE') fail('INVALID_DRIVER', 'Not an active driver', HttpStatus.UNPROCESSABLE_ENTITY);
    if (!vehicle || vehicle.status === 'MAINTENANCE' || vehicle.status === 'INACTIVE') fail('INVALID_VEHICLE', 'Vehicle is not available', HttpStatus.UNPROCESSABLE_ENTITY);
    const busy = await this.prisma.trip.findFirst({
      where: { id: { not: id }, status: { in: [...ACTIVE_FOR_DRIVER] }, OR: [{ driverId }, { vehicleId }] },
      select: { code: true, driverId: true },
    });
    if (busy) {
      fail(busy.driverId === driverId ? 'DRIVER_BUSY' : 'VEHICLE_BUSY', `Already on active trip ${busy.code}`, HttpStatus.CONFLICT);
    }
    const updated = await this.prisma.trip.update({ where: { id }, data: { driverId, vehicleId, status: 'ASSIGNED' } });
    if (trip.driverId && trip.driverId !== driverId) this.realtime.toUser(trip.driverId, 'trip.updated', { tripId: id, unassigned: true });
    this.notify(updated, { tripId: id, status: updated.status, driverId, vehicleId, by: user.id });
    return tripView(updated);
  }

  // ───────────── operator: load (FO-FR-11) ─────────────

  /** Scanned batches must be allocated to an order dropped by this trip ("wrong-batch" check). */
  async load(user: AuthUser, id: string, batchIds: string[]) {
    const trip = await this.loadForUser(user, id);
    this.assertCan(trip, 'load');
    if (user.role === 'OPERATOR' && user.siteId !== trip.depotSiteId) fail('FORBIDDEN_SITE', 'Load at the trip depot only', HttpStatus.FORBIDDEN);

    const stopOrders = (await this.prisma.tripStop.findMany({ where: { tripId: id, routeVersion: trip.currentRouteVersion, orderId: { not: null } }, select: { orderId: true } }))
      .map((s) => s.orderId as string);
    const allocated = await this.prisma.orderBatch.findMany({ where: { orderId: { in: stopOrders }, batchId: { in: batchIds } }, select: { batchId: true } });
    const allowed = new Set(allocated.map((a) => a.batchId));
    const wrong = batchIds.filter((b) => !allowed.has(b));
    if (wrong.length) fail('BATCH_NOT_ON_TRIP', 'Some scanned batches are not allocated to this trip', HttpStatus.CONFLICT, { batchIds: wrong });

    const vehicle = await this.prisma.vehicle.findUniqueOrThrow({ where: { id: trip.vehicleId }, select: { regNo: true } });
    const result = await this.prisma.$transaction(async (tx) => {
      const loaded: string[] = [];
      for (const batchId of batchIds) {
        const already = await tx.tripBatch.findUnique({ where: { tripId_batchId: { tripId: id, batchId } } });
        if (already) continue; // idempotent re-scan
        const b = await tx.batch.findUniqueOrThrow({ where: { id: batchId } });
        if (b.currentSiteId !== trip.depotSiteId) fail('BATCH_NOT_AT_DEPOT', `Batch ${b.code} is not at the depot`, HttpStatus.CONFLICT);
        if (b.storageUnitId) await this.storage.release(tx, b.storageUnitId, Number(b.weightKg));
        await tx.batch.update({ where: { id: batchId }, data: { status: 'LOADED', storageUnitId: null } });
        await tx.tripBatch.create({ data: { tripId: id, batchId, loadedBy: user.id, loadedAt: new Date() } });
        await this.trace.append(tx, batchId, 'LOADED', { tripCode: trip.code, vehicleRegNo: vehicle.regNo }, user.id);
        loaded.push(batchId);
      }
      // New cargo can change the valid setpoint: a passed pre-check must be repeated.
      if (loaded.length && trip.status === 'PRE_CHECK_DONE') await tx.trip.update({ where: { id }, data: { status: 'ASSIGNED' } });
      return loaded;
    });
    if (result.length) this.notify(trip, { tripId: id, loaded: result.length, precheckReset: trip.status === 'PRE_CHECK_DONE' });
    return { tripId: id, loaded: result, alreadyLoaded: batchIds.filter((b) => !result.includes(b)) };
  }

  // ───────────── driver: pre-check, start ─────────────

  async preCheck(user: AuthUser, id: string, dto: PreCheckDto) {
    const trip = await this.loadForUser(user, id);
    this.assertCan(trip, 'preCheck');
    const [vehicle, cargo] = await Promise.all([
      this.prisma.vehicle.findUniqueOrThrow({ where: { id: trip.vehicleId } }),
      this.prisma.tripBatch.findMany({ where: { tripId: id, unloadedAt: null }, include: { batch: { include: { product: true } } } }),
    ]);
    const allowed = allowedSetpoint(
      cargo.map((c) => ({ min: Number(c.batch.product.safeTempMin), max: Number(c.batch.product.safeTempMax) })),
      { min: Number(vehicle.reeferMinTemp), max: Number(vehicle.reeferMaxTemp) },
    );
    const problems = preCheckProblems(dto, allowed);
    const passed = problems.length === 0;
    const eventId = dto.id ?? randomUUID();
    await this.prisma.$transaction(async (tx) => {
      // Saved with timestamp whether or not it passed (DA-FR-03).
      await tx.tripEvent.upsert({
        where: { id: eventId },
        update: {},
        create: { id: eventId, tripId: id, type: 'PRE_TRIP_CHECK', payload: { ...dto, allowed, passed, problems } as unknown as Prisma.InputJsonValue, occurredAt: dto.occurredAt ? new Date(dto.occurredAt) : new Date() },
      });
      if (passed) await tx.trip.update({ where: { id }, data: { status: 'PRE_CHECK_DONE' } });
    });
    if (!passed) fail('PRE_CHECK_FAILED', 'Pre-trip check failed', HttpStatus.UNPROCESSABLE_ENTITY, { problems, allowed });
    this.notify(trip, { tripId: id, status: 'PRE_CHECK_DONE' });
    return { tripId: id, status: 'PRE_CHECK_DONE', allowed };
  }

  /** DA-FR-01: binds this device + vehicle to the trip. One active trip per driver and per vehicle. */
  async start(user: AuthUser, id: string, deviceId: string | undefined) {
    const trip = await this.loadForUser(user, id);
    if (trip.status === 'PLANNED' || trip.status === 'ASSIGNED') fail('PRE_CHECK_REQUIRED', 'Complete the pre-trip check first', HttpStatus.CONFLICT);
    this.assertCan(trip, 'start');
    if (!deviceId) fail('MISSING_DEVICE_ID', 'X-Device-Id header is required', HttpStatus.BAD_REQUEST);
    if (trip.boundDeviceId && trip.boundDeviceId !== deviceId) fail('TRIP_ON_OTHER_DEVICE', 'This trip is bound to another phone', HttpStatus.CONFLICT);
    const clash = await this.prisma.trip.findFirst({
      where: { id: { not: id }, status: 'IN_PROGRESS', OR: [{ driverId: trip.driverId }, { vehicleId: trip.vehicleId }] },
      select: { code: true, driverId: true },
    });
    if (clash) fail(clash.driverId === trip.driverId ? 'DRIVER_ON_OTHER_TRIP' : 'VEHICLE_IN_USE', `Trip ${clash.code} is in progress`, HttpStatus.CONFLICT);
    const cargo = await this.prisma.tripBatch.findMany({ where: { tripId: id }, select: { batchId: true } });
    if (!cargo.length) fail('NOTHING_LOADED', 'No batches are loaded on this trip', HttpStatus.CONFLICT);

    const now = new Date();
    const updated = await this.prisma.$transaction(async (tx) => {
      const flipped = await tx.trip.updateMany({ where: { id, status: 'PRE_CHECK_DONE' }, data: { status: 'IN_PROGRESS', startedAt: now, boundDeviceId: deviceId } });
      if (flipped.count !== 1) fail('INVALID_TRIP_STATUS', 'Trip state changed; reload', HttpStatus.CONFLICT);
      await tx.vehicle.update({ where: { id: trip.vehicleId }, data: { status: 'IN_USE' } });
      await tx.tripStop.updateMany({ where: { tripId: id, routeVersion: trip.currentRouteVersion, type: 'PICKUP', status: 'PENDING' }, data: { status: 'COMPLETED', arrivedAt: now, completedAt: now } });
      await tx.tripEvent.create({ data: { id: randomUUID(), tripId: id, type: 'START', payload: { deviceId }, occurredAt: now } });
      for (const { batchId } of cargo) {
        await tx.batch.update({ where: { id: batchId }, data: { status: 'IN_TRANSIT' } });
        await this.trace.append(tx, batchId, 'DEPARTED', { tripCode: trip.code }, user.id, now);
      }
      const orderIds = (await tx.tripStop.findMany({ where: { tripId: id, orderId: { not: null } }, select: { orderId: true } })).map((s) => s.orderId as string);
      await tx.dispatchOrder.updateMany({ where: { id: { in: orderIds }, status: 'PLANNED' }, data: { status: 'IN_TRANSIT' } });
      return tx.trip.findUniqueOrThrow({ where: { id } });
    });
    this.notify(updated, { tripId: id, status: 'IN_PROGRESS', startedAt: now });
    await this.events.publish('order-transactions', id, { type: 'TRIP_STARTED', tripId: id });
    return tripView(updated);
  }

  // ───────────── driver: events, SOS (DA-FR-09, DA-FR-14) ─────────────

  async recordEvent(user: AuthUser, id: string, dto: TripEventDto) {
    const trip = await this.loadForUser(user, id);
    const existing = await this.prisma.tripEvent.findUnique({ where: { id: dto.id } });
    if (existing) {
      if (existing.tripId !== id) fail('DUPLICATE', 'Event id already used', HttpStatus.CONFLICT);
      return existing; // idempotent replay (offline outbox)
    }
    this.assertCan(trip, 'event');
    if (dto.photoKey) await this.files.verifyOwnUpload(user, dto.photoKey, 'INCIDENT_PHOTO');
    if (dto.voiceKey) await this.files.verifyOwnUpload(user, dto.voiceKey, 'VOICE_NOTE');

    const event = await this.prisma.tripEvent.create({
      data: {
        id: dto.id, tripId: id, type: dto.type as TripEventType, payload: (dto.payload ?? {}) as Prisma.InputJsonValue,
        photoKey: dto.photoKey, voiceKey: dto.voiceKey, lat: dto.lat, lng: dto.lng, occurredAt: new Date(dto.occurredAt),
      },
    });

    if (dto.type === 'SOS') {
      await this.raiseSos(user, trip, event.id, dto);
    } else {
      // The incident engine (worker, Kafka topic alerts) classifies these: replan / divert / rescue (M9).
      this.realtime.toManagers('incident.updated', { tripId: id, tripCode: trip.code, eventId: event.id, type: dto.type, lat: dto.lat, lng: dto.lng, reported: true });
      await this.events.publish('alerts', id, { type: 'DRIVER_INCIDENT', tripId: id, eventId: event.id, kind: dto.type });
    }
    return event;
  }

  /** SOS: CRITICAL alert + realtime to managers; SMS with the location to the emergency contact. */
  private async raiseSos(user: AuthUser, trip: Trip, eventId: string, dto: TripEventDto) {
    const driver = await this.prisma.user.findUniqueOrThrow({ where: { id: user.id }, select: { name: true, phone: true, emergencyContactPhone: true } });
    const where = dto.lat !== undefined && dto.lng !== undefined ? mapsLink(dto.lat, dto.lng) : 'location unknown';
    // Managers get it through the alert chain (in-app + push + verified email).
    const alert = await this.alerts.raise({
      type: 'SOS',
      severity: 'CRITICAL',
      tripId: trip.id,
      vehicleId: trip.vehicleId,
      message: `SOS from ${driver.name} on trip ${trip.code}. ${where}`,
      data: { eventId, lat: dto.lat ?? null, lng: dto.lng ?? null, map: where, driverPhone: driver.phone },
    });
    if (driver.emergencyContactPhone) {
      try {
        await this.sms.send(driver.emergencyContactPhone, `I-CCMS SOS: ${driver.name} needs help (trip ${trip.code}). ${where}`, { priority: 'alert', alertId: alert.id });
      } catch (e) {
        this.logger.error({ msg: 'SOS SMS to emergency contact failed', tripId: trip.id, error: (e as Error).message });
      }
    } else {
      this.logger.warn({ msg: 'SOS: driver has no emergency contact', userId: user.id });
    }
  }

  // ───────────── driver: route response, arrive ─────────────

  /** DA-FR-08. Declining is refused for incident/diversion/rescue replans (Section 10.5). */
  async respondRoute(user: AuthUser, id: string, version: number, accept: boolean) {
    const trip = await this.loadForUser(user, id);
    this.assertCan(trip, 'routeResponse');
    const plan = await this.prisma.routePlan.findUnique({ where: { tripId_version: { tripId: id, version } } });
    if (!plan) fail('NOT_FOUND', 'Route version not found', HttpStatus.NOT_FOUND);
    if (plan.status !== 'PROPOSED') {
      if ((accept && plan.status === 'ACCEPTED') || (!accept && plan.status === 'DECLINED')) return plan; // idempotent replay
      fail('ROUTE_NOT_PROPOSED', `Route v${version} is ${plan.status}`, HttpStatus.CONFLICT);
    }
    if (!accept && ['INCIDENT', 'DIVERSION', 'RESCUE'].includes(plan.reason)) {
      fail('DECLINE_NOT_ALLOWED', 'This reroute protects the cargo and must be accepted', HttpStatus.CONFLICT);
    }
    const now = new Date();
    const result = await this.prisma.$transaction(async (tx) => {
      if (accept) {
        await tx.routePlan.updateMany({ where: { tripId: id, status: 'ACCEPTED' }, data: { status: 'SUPERSEDED' } });
        const dropped = await tx.tripStop.findMany({ where: { tripId: id, routeVersion: trip.currentRouteVersion, status: { in: ['PENDING', 'ARRIVED'] }, orderId: { not: null } }, select: { orderId: true } });
        await tx.tripStop.updateMany({ where: { tripId: id, routeVersion: trip.currentRouteVersion, status: { in: ['PENDING', 'ARRIVED'] } }, data: { status: 'CANCELLED' } });
        await tx.trip.update({ where: { id }, data: { currentRouteVersion: version } });
        // Orders whose drop left this route and is not on any live route (this one or a rescue truck's) are cancelled.
        for (const orderId of new Set(dropped.map((d) => d.orderId as string))) {
          const live = await tx.tripStop.count({ where: { orderId, status: { in: ['PENDING', 'ARRIVED'] } } });
          if (!live) await tx.dispatchOrder.updateMany({ where: { id: orderId, status: { in: ['PLANNED', 'IN_TRANSIT'] } }, data: { status: 'CANCELLED' } });
        }
      }
      return tx.routePlan.update({ where: { id: plan.id }, data: { status: accept ? 'ACCEPTED' : 'DECLINED', respondedAt: now } });
    });
    const payload = { tripId: id, version, status: result.status, reason: plan.reason };
    this.realtime.toTrip(id, 'route.updated', payload);
    this.realtime.toManagers('route.updated', payload);
    try {
      if (accept) await this.incidents?.onRouteAccepted(id, version, plan.reason);
      else await this.incidents?.onRouteDeclined(id, version);
    } catch (e) {
      this.logger.error({ msg: 'incident hook failed after route response', tripId: id, error: (e as Error).message });
    }
    return result;
  }

  async arrive(user: AuthUser, id: string, stopId: string, dto: ArriveDto) {
    const trip = await this.loadForUser(user, id);
    this.assertCan(trip, 'arrive');
    const stop = await this.prisma.tripStop.findUnique({ where: { id: stopId } });
    if (!stop || stop.tripId !== id || stop.routeVersion !== trip.currentRouteVersion) fail('NOT_FOUND', 'Stop not on the current route', HttpStatus.NOT_FOUND);
    if (stop.status !== 'PENDING') return stop; // already arrived (offline replay)
    const at = dto.arrivedAt ? new Date(dto.arrivedAt) : new Date();
    const updated = await this.prisma.$transaction(async (tx) => {
      await tx.tripEvent.create({ data: { id: randomUUID(), tripId: id, type: 'ARRIVE', payload: { stopId, seq: stop.seq }, lat: dto.lat, lng: dto.lng, occurredAt: at } });
      return tx.tripStop.update({ where: { id: stopId }, data: { status: 'ARRIVED', arrivedAt: at } });
    });
    this.notify(trip, { tripId: id, stopId, stopStatus: 'ARRIVED' });
    return updated;
  }

  // ───────────── completion (used by PoD) ─────────────

  /** All stops of the current route done → COMPLETED, vehicle free, CO₂ (SYN-16). Inside the PoD transaction. */
  async completeIfDone(tx: Tx, tripId: string, factorKgPerKm: number): Promise<boolean> {
    const trip = await tx.trip.findUniqueOrThrow({ where: { id: tripId } });
    if (trip.status !== 'IN_PROGRESS') return false;
    const open = await tx.tripStop.count({ where: { tripId, routeVersion: trip.currentRouteVersion, status: { notIn: STOP_DONE as never } } });
    if (open) return false;
    const now = new Date();
    const distance = trip.distanceKm === null ? 0 : Number(trip.distanceKm);
    await tx.trip.update({ where: { id: tripId }, data: { status: 'COMPLETED', completedAt: now, co2Kg: co2Kg(distance, factorKgPerKm) } });
    await tx.vehicle.update({ where: { id: trip.vehicleId }, data: { status: 'AVAILABLE' } });
    await tx.tripEvent.create({ data: { id: randomUUID(), tripId, type: 'COMPLETE', payload: { distanceKm: distance, co2Kg: co2Kg(distance, factorKgPerKm) }, occurredAt: now } });
    return true;
  }

  async emissionFactor(): Promise<number> {
    return (await this.config.get('emissionFactorKgPerKm')).value;
  }

  publishTripDone(trip: Pick<Trip, 'id' | 'driverId'>) {
    this.notify(trip, { tripId: trip.id, status: 'COMPLETED' });
    return this.events.publish('order-transactions', trip.id, { type: 'TRIP_COMPLETED', tripId: trip.id });
  }
}
