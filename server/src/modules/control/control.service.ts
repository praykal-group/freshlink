import { Injectable, Optional } from '@nestjs/common';
import type { AppFlavor, BatchStatus } from '@prisma/client';
import { istAt, istDay } from '../../common/ist';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { TelemetryService } from '../telemetry/telemetry.service';
import { OPEN_DROPS } from '../trips/trip-rules';

/** Batches still in the chain (not delivered, rejected or spoiled). */
const LIVE: BatchStatus[] = ['REGISTERED', 'GRADED', 'STORED', 'ALLOCATED', 'LOADED', 'IN_TRANSIT', 'DIVERTED'];
/** Section 10.6 #1 "at-risk batches < 12 h". */
export const AT_RISK_HOURS = 12;
/** Window of the "spoilage avoided" KPI. */
export const AVOIDED_DAYS = 30;
const FLAVORS: AppFlavor[] = ['driver', 'operator', 'manager', 'web'];

/**
 * Control tower reads (M13): dashboard KPIs + live vehicle positions, drivers for assignment
 * (the user admin is ADMIN-only) and the app releases list.
 */
@Injectable()
export class ControlService {
  constructor(
    private readonly prisma: PrismaService,
    @Optional() private readonly telemetry?: TelemetryService,
  ) {}

  /** Section 10.6 #1. `spoilageAvoidedKg` = kg accepted at diversion / cold-storage / rescue drops in the last 30 days. */
  async summary(now = new Date()) {
    const day = istDay(now);
    const from = istAt(day), to = istAt(day, '24:00');
    const since = new Date(now.getTime() - AVOIDED_DAYS * 24 * 3600 * 1000);
    const [activeTrips, openCriticalAlerts, atRiskBatches, deliveredStops, avoided, trips] = await Promise.all([
      this.prisma.trip.count({ where: { status: 'IN_PROGRESS' } }),
      this.prisma.alert.count({ where: { severity: 'CRITICAL', status: { in: ['OPEN', 'ESCALATED'] } } }),
      this.prisma.batch.count({ where: { status: { in: LIVE }, remainingShelfLifeH: { lt: AT_RISK_HOURS } } }),
      this.prisma.proofOfDelivery.groupBy({ by: ['tripStopId'], where: { capturedAt: { gte: from, lt: to } } }),
      this.prisma.proofOfDelivery.aggregate({ _sum: { acceptedKg: true }, where: { capturedAt: { gte: since }, tripStop: { type: { in: [...OPEN_DROPS] as never } } } }),
      this.prisma.trip.findMany({
        where: { status: 'IN_PROGRESS' },
        select: { id: true, code: true, vehicleId: true, vehicle: { select: { regNo: true } }, driver: { select: { name: true } } },
        orderBy: { code: 'asc' },
      }),
    ]);
    const vehicles = await Promise.all(
      trips.map(async (t) => {
        const r = await this.telemetry?.lastReading(t.vehicleId).catch(() => null);
        return {
          vehicleId: t.vehicleId, regNo: t.vehicle.regNo, tripId: t.id, tripCode: t.code, driverName: t.driver?.name ?? null,
          lat: r?.lat ?? null, lng: r?.lng ?? null, tempC: r?.tempC ?? null, at: r?.ts ?? null,
        };
      }),
    );
    return {
      date: day,
      kpis: { activeTrips, openCriticalAlerts, atRiskBatches, deliveriesToday: deliveredStops.length, spoilageAvoidedKg: Number(avoided._sum.acceptedKg ?? 0) },
      vehicles,
    };
  }

  /** Active drivers with whether they already have a trip (assign screen, Section 10.6 #5). */
  async drivers() {
    const [users, busy] = await Promise.all([
      this.prisma.user.findMany({ where: { role: 'DRIVER', status: 'ACTIVE' }, select: { id: true, name: true, phone: true, siteId: true }, orderBy: { name: 'asc' } }),
      this.prisma.trip.findMany({ where: { status: { in: ['ASSIGNED', 'PRE_CHECK_DONE', 'IN_PROGRESS'] }, driverId: { not: null } }, select: { driverId: true, code: true } }),
    ]);
    const byDriver = new Map(busy.map((b) => [b.driverId!, b.code]));
    return { items: users.map((u) => ({ ...u, busyTripCode: byDriver.get(u.id) ?? null })) };
  }

  /** Section 10.6 #11: read-only list of active releases, newest first (filled by the release sync in M15). */
  async releases(flavor?: string) {
    const f = FLAVORS.find((x) => x === flavor);
    const rows = await this.prisma.appRelease.findMany({
      where: { isActive: true, ...(f ? { flavor: f } : {}) },
      orderBy: [{ flavor: 'asc' }, { versionCode: 'desc' }],
      select: { id: true, flavor: true, channel: true, versionName: true, versionCode: true, minSupportedCode: true, mandatory: true, publishedAt: true, sizeBytes: true, features: true, improvements: true, fixes: true },
    });
    return { items: rows.map((r) => ({ ...r, sizeBytes: Number(r.sizeBytes) })) };
  }
}
