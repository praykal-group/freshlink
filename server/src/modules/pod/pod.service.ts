import { HttpStatus, Injectable, Logger, Optional } from '@nestjs/common';
import type { BatchStatus } from '@prisma/client';
import type { AuthUser } from '../../common/auth/auth-user';
import { AppError } from '../../common/errors/app-error';
import { EventBus } from '../../infra/events/event-bus.service';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { FilesService } from '../files/files.service';
import { IncidentsService } from '../incidents/incidents.service';
import { TraceService } from '../trace/trace.service';
import type { PodDto, PodItemDto } from '../trips/dto/trip.dto';
import { TripsService } from '../trips/trips.service';

function fail(code: string, message: string, status: HttpStatus, details?: Record<string, unknown>): never {
  throw new AppError(code, message, status, details);
}

/** Stop types where any batch on board may be handed over (no single order behind the stop). */
const OPEN_DROPS = ['DIVERSION_DROP', 'COLD_STORAGE_DROP', 'RESCUE_DROP'];

export function checkOutcome(item: Pick<PodItemDto, 'outcome' | 'acceptedKg' | 'reason'>, weightKg: number): string | null {
  if (item.outcome === 'ACCEPTED' && Math.abs(item.acceptedKg - weightKg) > 1e-6) return `ACCEPTED must accept the full ${weightKg} kg`;
  if (item.outcome === 'PARTIAL' && !(item.acceptedKg > 0 && item.acceptedKg < weightKg)) return `PARTIAL needs 0 < acceptedKg < ${weightKg}`;
  if (item.outcome === 'REJECTED' && item.acceptedKg !== 0) return 'REJECTED must have acceptedKg 0';
  if (item.outcome !== 'ACCEPTED' && !item.reason?.trim()) return 'A reason is required for PARTIAL and REJECTED';
  return null;
}

export const batchStatusFor = (outcome: PodItemDto['outcome']): BatchStatus =>
  outcome === 'ACCEPTED' ? 'DELIVERED' : outcome === 'PARTIAL' ? 'PARTIALLY_DELIVERED' : 'REJECTED';

/** Proof of delivery (DA-FR-11/12). Rows are idempotent on their client UUIDs. */
@Injectable()
export class PodService {
  private readonly logger = new Logger(PodService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly trips: TripsService,
    private readonly files: FilesService,
    private readonly trace: TraceService,
    private readonly events: EventBus,
    @Optional() private readonly incidents?: IncidentsService,
  ) {}

  async submit(user: AuthUser, tripId: string, stopId: string, dto: PodDto) {
    const trip = await this.trips.loadForUser(user, tripId);
    const stop = await this.prisma.tripStop.findUnique({ where: { id: stopId }, include: { site: { select: { code: true } } } });
    if (!stop || stop.tripId !== tripId) fail('NOT_FOUND', 'Stop not on this trip', HttpStatus.NOT_FOUND);

    // Replays first: rows already stored are not re-validated (offline outbox).
    const existing = await this.prisma.proofOfDelivery.findMany({ where: { id: { in: dto.items.map((i) => i.id) } } });
    const known = new Set(existing.map((e) => e.id));
    const fresh = dto.items.filter((i) => !known.has(i.id));
    if (!fresh.length) return { stopId, stored: [], replayed: existing.map((e) => e.id), tripCompleted: trip.status === 'COMPLETED' };

    this.trips.assertCan(trip, 'pod');
    if (stop.routeVersion !== trip.currentRouteVersion) fail('STOP_SUPERSEDED', 'This stop is no longer on the current route', HttpStatus.CONFLICT);
    if (stop.type === 'PICKUP' || stop.type === 'RESCUE_PICKUP') fail('NOT_A_DROP', 'PoD is only for drop stops', HttpStatus.CONFLICT);
    if (stop.status === 'COMPLETED' || stop.status === 'CANCELLED') fail('STOP_CLOSED', `Stop is ${stop.status}`, HttpStatus.CONFLICT);
    await Promise.all([this.files.verifyOwnUpload(user, dto.signatureKey, 'POD_SIGNATURE'), this.files.verifyOwnUpload(user, dto.photoKey, 'POD_PHOTO')]);

    const onBoard = await this.prisma.tripBatch.findMany({
      where: { tripId, unloadedAt: null, batchId: { in: fresh.map((i) => i.batchId) } },
      include: { batch: { include: { tags: { select: { tagUid: true } } } } },
    });
    const byId = new Map(onBoard.map((tb) => [tb.batchId, tb.batch]));
    const expected = stop.orderId ? new Set((await this.prisma.orderBatch.findMany({ where: { orderId: stop.orderId } })).map((o) => o.batchId)) : null;
    const problems: Record<string, string> = {};
    for (const item of fresh) {
      const b = byId.get(item.batchId);
      if (!b) problems[item.batchId] = 'not on board this trip';
      else if (expected && !OPEN_DROPS.includes(stop.type) && !expected.has(item.batchId)) problems[item.batchId] = 'not for this stop';
      else if (item.scannedTagUid !== b.code && !b.tags.some((t) => t.tagUid === item.scannedTagUid)) problems[item.batchId] = 'scanned tag does not belong to this batch';
      else {
        const err = checkOutcome(item, Number(b.weightKg));
        if (err) problems[item.batchId] = err;
      }
    }
    if (Object.keys(problems).length) {
      const tag = Object.values(problems).some((p) => p.startsWith('scanned tag'));
      fail(tag ? 'TAG_MISMATCH' : 'INVALID_POD', 'Some PoD items are not valid', tag ? HttpStatus.CONFLICT : HttpStatus.UNPROCESSABLE_ENTITY, { problems });
    }

    // RESCUE_DROP = handover to the rescue truck (W-2 b): the batches move to that trip, not delivered.
    const rescueTripId = stop.type === 'RESCUE_DROP' ? await this.incidents?.rescueTripFor(tripId) : null;
    if (stop.type === 'RESCUE_DROP') {
      if (!rescueTripId) fail('NO_RESCUE_TRIP', 'No rescue truck is assigned to this handover', HttpStatus.CONFLICT);
      if (fresh.some((i) => i.outcome !== 'ACCEPTED')) fail('INVALID_POD', 'A rescue handover moves whole batches (outcome ACCEPTED)', HttpStatus.UNPROCESSABLE_ENTITY);
    }
    const rescueTrip = rescueTripId ? await this.prisma.trip.findUniqueOrThrow({ where: { id: rescueTripId }, select: { id: true, code: true } }) : null;

    const factor = await this.trips.emissionFactor();
    const capturedAt = new Date(dto.capturedAt);
    const result = await this.prisma.$transaction(async (tx) => {
      if (stop.status === 'PENDING') await tx.tripStop.update({ where: { id: stopId }, data: { status: 'ARRIVED', arrivedAt: capturedAt } });
      for (const item of fresh) {
        const b = byId.get(item.batchId)!;
        if (rescueTrip) {
          await tx.proofOfDelivery.create({
            data: {
              id: item.id, tripStopId: stopId, batchId: item.batchId, outcome: 'ACCEPTED', acceptedKg: item.acceptedKg, reason: item.reason,
              receiverName: dto.receiverName, signatureKey: dto.signatureKey, photoKey: dto.photoKey, scannedTagUid: item.scannedTagUid,
              capturedAt, lat: dto.lat, lng: dto.lng,
            },
          });
          await tx.tripBatch.update({ where: { tripId_batchId: { tripId, batchId: item.batchId } }, data: { unloadedAt: capturedAt } });
          await tx.tripBatch.upsert({
            where: { tripId_batchId: { tripId: rescueTrip.id, batchId: item.batchId } },
            update: { unloadedAt: null },
            create: { tripId: rescueTrip.id, batchId: item.batchId, loadedBy: user.id, loadedAt: capturedAt },
          });
          await tx.batch.update({ where: { id: item.batchId }, data: { status: 'IN_TRANSIT' } });
          await this.trace.append(tx, item.batchId, 'RESCUED', { fromTripCode: trip.code, toTripCode: rescueTrip.code, receiverName: dto.receiverName, weightKg: Number(b.weightKg) }, user.id, capturedAt);
          continue;
        }
        await tx.proofOfDelivery.create({
          data: {
            id: item.id, tripStopId: stopId, batchId: item.batchId, outcome: item.outcome, acceptedKg: item.acceptedKg, reason: item.reason,
            receiverName: dto.receiverName, signatureKey: dto.signatureKey, photoKey: dto.photoKey, scannedTagUid: item.scannedTagUid,
            capturedAt, lat: dto.lat, lng: dto.lng,
          },
        });
        const delivered = item.outcome !== 'REJECTED';
        await tx.batch.update({
          where: { id: item.batchId },
          data: { status: batchStatusFor(item.outcome), ...(delivered && stop.siteId ? { currentSiteId: stop.siteId } : {}) },
        });
        await tx.tripBatch.update({ where: { tripId_batchId: { tripId, batchId: item.batchId } }, data: { unloadedAt: capturedAt } });
        await this.trace.append(
          tx,
          item.batchId,
          delivered ? 'DELIVERED' : 'REJECTED',
          { tripCode: trip.code, stopType: stop.type, siteCode: stop.site?.code ?? null, outcome: item.outcome, acceptedKg: item.acceptedKg, weightKg: Number(b.weightKg), reason: item.reason ?? null, receiverName: dto.receiverName },
          user.id,
          capturedAt,
        );
      }
      // Stop done when every batch expected here has a PoD (open drops: done on first submission).
      let stopDone = true;
      if (expected && !OPEN_DROPS.includes(stop.type)) {
        const podded = await tx.proofOfDelivery.findMany({ where: { tripStopId: stopId }, select: { batchId: true } });
        const onTrip = await tx.tripBatch.findMany({ where: { tripId, batchId: { in: [...expected] } }, select: { batchId: true } });
        const done = new Set(podded.map((p) => p.batchId));
        stopDone = onTrip.every((t) => done.has(t.batchId));
      }
      if (stopDone) {
        await tx.tripStop.update({ where: { id: stopId }, data: { status: 'COMPLETED', completedAt: capturedAt } });
        if (stop.orderId) await tx.dispatchOrder.update({ where: { id: stop.orderId }, data: { status: 'DELIVERED' } });
      }
      // The rescue truck's pickup is done once the cargo has been handed over.
      if (rescueTrip && stopDone) {
        await tx.tripStop.updateMany({
          where: { tripId: rescueTrip.id, type: 'RESCUE_PICKUP', status: { in: ['PENDING', 'ARRIVED'] } },
          data: { status: 'COMPLETED', completedAt: capturedAt },
        });
      }
      const tripCompleted = await this.trips.completeIfDone(tx, tripId, factor);
      return { stopDone, tripCompleted };
    });

    await this.events.publish('order-transactions', stopId, { type: 'POD', tripId, stopId, items: fresh.map((i) => ({ batchId: i.batchId, outcome: i.outcome })) });
    if (result.tripCompleted) await this.trips.publishTripDone(trip);
    if (result.stopDone) {
      await this.incidents?.onDropCompleted(tripId, stop.type).catch((e: Error) => this.logger.error({ msg: 'incident hook failed after PoD', tripId, error: e.message }));
    }
    return { stopId, stored: fresh.map((i) => i.id), replayed: [...known], stopCompleted: result.stopDone, tripCompleted: result.tripCompleted };
  }
}
