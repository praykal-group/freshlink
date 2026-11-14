import { HttpStatus, Injectable, Logger } from '@nestjs/common';
import { AppError } from '../../common/errors/app-error';
import { toCsv } from '../../common/csv-write';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { RemoteConfigService } from '../remote-config/remote-config.service';
import { TelemetryService } from '../telemetry/telemetry.service';
import { TraceService } from '../trace/trace.service';
import { cteOf, excursions, parseRange, type TempRow, tempStats } from './report-rules';

const IST_OFFSET_MS = 5.5 * 3_600_000;
const ist = (d: Date | string) => new Date(new Date(d).getTime() + IST_OFFSET_MS).toISOString().replace('T', ' ').slice(0, 19);
const MAX_TRIP_RANGE_MS = 31 * 86_400_000;
const MAX_TRACE_ROWS = 50_000;

/**
 * Reports (SYN-15/16/17, Section 6.4 "Reports"). Temperature logs come from InfluxDB at 1-minute
 * resolution (mean per minute, the same query as the manager chart), so the report matches the
 * stored telemetry. If InfluxDB cannot be read the report still opens and says so.
 */
@Injectable()
export class ReportsService {
  private readonly logger = new Logger(ReportsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly telemetry: TelemetryService,
    private readonly trace: TraceService,
    private readonly config: RemoteConfigService,
  ) {}

  /** HACCP-style temperature record for one batch (EN 12830-style recorder data, 1-min). */
  async compliance(batchId: string) {
    const batch = await this.prisma.batch.findUnique({
      where: { id: batchId },
      include: { product: true, sourceSite: { select: { code: true, name: true } }, currentSite: { select: { code: true, name: true } } },
    });
    if (!batch) throw new AppError('NOT_FOUND', 'Batch not found', HttpStatus.NOT_FOUND);
    const safeMin = Number(batch.product.safeTempMin);
    const safeMax = Number(batch.product.safeTempMax);
    const [events, pods, legs, verdict] = await Promise.all([
      this.prisma.traceEvent.findMany({ where: { batchId }, orderBy: { seq: 'asc' } }),
      this.prisma.proofOfDelivery.findMany({ where: { batchId }, include: { tripStop: { select: { type: true, trip: { select: { code: true } }, site: { select: { code: true, name: true } }, buyer: { select: { name: true } } } } } }),
      this.prisma.tripBatch.findMany({ where: { batchId }, include: { trip: { include: { vehicle: { select: { regNo: true } } } } }, orderBy: { loadedAt: 'asc' } }),
      this.trace.verify(batchId),
    ]);

    const trips = [];
    const all: (TempRow & { tripCode: string; humidityPct: number | null })[] = [];
    for (const leg of legs) {
      const from = leg.loadedAt;
      let to = leg.unloadedAt ?? leg.trip.completedAt ?? new Date();
      if (to.getTime() - from.getTime() > MAX_TRIP_RANGE_MS) to = new Date(from.getTime() + MAX_TRIP_RANGE_MS);
      let rows: (TempRow & { humidityPct: number | null })[] = [];
      let telemetryNote: string | null = null;
      if (to > from) {
        try {
          const s = await this.telemetry.tripSeries(leg.tripId, from, to, '1m');
          rows = (s.points as Record<string, unknown>[])
            .filter((p) => typeof p.temp_c === 'number')
            .map((p) => ({ at: String(p.at), tempC: p.temp_c as number, humidityPct: typeof p.humidity_pct === 'number' ? (p.humidity_pct as number) : null }));
        } catch (e) {
          telemetryNote = `Telemetry could not be read: ${(e as Error).message}`;
          this.logger.warn({ msg: 'compliance: telemetry unavailable', batchId, tripId: leg.tripId, error: (e as Error).message });
        }
      }
      if (!rows.length && !telemetryNote) telemetryNote = 'No temperature readings were stored for this leg.';
      all.push(...rows.map((r) => ({ ...r, tripCode: leg.trip.code })));
      const alerts = await this.prisma.alert.findMany({ where: { tripId: leg.tripId, type: { in: ['TEMP_EXCURSION', 'HUMIDITY', 'ETHYLENE', 'SHOCK'] }, createdAt: { gte: from, lte: to } }, orderBy: { createdAt: 'asc' } });
      trips.push({
        tripCode: leg.trip.code,
        vehicle: leg.trip.vehicle.regNo,
        from: from.toISOString(),
        to: to.toISOString(),
        stats: tempStats(rows),
        excursions: excursions(rows, safeMin, safeMax),
        alerts: alerts.map((a) => ({ at: a.createdAt.toISOString(), type: a.type, severity: a.severity, status: a.status, message: a.message })),
        telemetryNote,
      });
    }

    return {
      batch: {
        id: batch.id, code: batch.code, status: batch.status, grade: batch.currentGrade, weightKg: Number(batch.weightKg),
        caughtOrHarvestedAt: batch.caughtOrHarvestedAt.toISOString(), sourceSite: batch.sourceSite, currentSite: batch.currentSite,
      },
      product: { code: batch.product.code, name: batch.product.name, safeTempMin: safeMin, safeTempMax: safeMax },
      summary: { ...tempStats(all), excursions: excursions(all, safeMin, safeMax), resolution: '1 min (mean per minute)' },
      trips,
      log: all,
      events: events.map((e) => ({ seq: e.seq, eventType: e.eventType, occurredAt: e.occurredAt.toISOString(), payload: e.payload, hash: e.hash })),
      chain: verdict,
      pods: pods.map((p) => ({
        tripCode: p.tripStop.trip.code, stopType: p.tripStop.type, place: p.tripStop.site?.name ?? p.tripStop.buyer?.name ?? null, outcome: p.outcome,
        acceptedKg: Number(p.acceptedKg), receiverName: p.receiverName, reason: p.reason, capturedAt: p.capturedAt.toISOString(),
      })),
      generatedAt: new Date().toISOString(),
    };
  }

  complianceCsv(r: Awaited<ReturnType<ReportsService['compliance']>>): string {
    return toCsv(
      ['batch_code', 'product', 'trip_code', 'time_utc', 'time_ist', 'temp_c', 'humidity_pct', 'safe_min_c', 'safe_max_c', 'in_range'],
      r.log.map((row) => [r.batch.code, r.product.code, row.tripCode, row.at, ist(row.at), row.tempC, row.humidityPct, r.product.safeTempMin, r.product.safeTempMax, row.tempC >= r.product.safeTempMin && row.tempC <= r.product.safeTempMax ? 'yes' : 'no']),
    );
  }

  complianceView(r: Awaited<ReturnType<ReportsService['compliance']>>) {
    const fmt = (v: number | null) => (v === null ? '–' : v.toFixed(2));
    return {
      ...r,
      generatedIst: ist(r.generatedAt),
      caughtIst: ist(r.batch.caughtOrHarvestedAt),
      summaryText: { min: fmt(r.summary.minC), max: fmt(r.summary.maxC), mean: fmt(r.summary.meanC) },
      trips: r.trips.map((t) => ({
        ...t, fromIst: ist(t.from), toIst: ist(t.to),
        statsText: { min: fmt(t.stats.minC), max: fmt(t.stats.maxC), mean: fmt(t.stats.meanC) },
        excursions: t.excursions.map((e) => ({ ...e, fromIst: ist(e.from), toIst: ist(e.to) })),
        alerts: t.alerts.map((a) => ({ ...a, atIst: ist(a.at) })),
      })),
      events: r.events.map((e) => ({ ...e, atIst: ist(e.occurredAt), payloadText: JSON.stringify(e.payload) })),
      pods: r.pods.map((p) => ({ ...p, atIst: ist(p.capturedAt) })),
      hasExcursions: r.summary.excursions.length > 0,
    };
  }

  /** FSMA 204-style KDE export: one row per Critical Tracking Event in the range (D-106). */
  async traceability(fromQ?: string, toQ?: string): Promise<string> {
    const range = parseRange(fromQ, toQ, 92);
    if (typeof range === 'string') throw new AppError('VALIDATION_FAILED', range, HttpStatus.UNPROCESSABLE_ENTITY);
    const events = await this.prisma.traceEvent.findMany({
      where: { occurredAt: { gte: range.from, lt: range.to } },
      include: { batch: { include: { product: { select: { code: true, name: true, category: true } }, sourceSite: { select: { code: true, name: true } } } } },
      orderBy: [{ occurredAt: 'asc' }, { id: 'asc' }],
      take: MAX_TRACE_ROWS + 1,
    });
    if (events.length > MAX_TRACE_ROWS) throw new AppError('RANGE_TOO_LARGE', `More than ${MAX_TRACE_ROWS} events: use a shorter range`, HttpStatus.UNPROCESSABLE_ENTITY);
    const rows: unknown[][] = [];
    for (const e of events) {
      const cte = cteOf(e.eventType, e.batch.product.category);
      if (!cte) continue;
      const p = (e.payload ?? {}) as Record<string, unknown>;
      const location = e.eventType === 'REGISTERED' ? `${e.batch.sourceSite.code} ${e.batch.sourceSite.name}` : String(p.siteCode ?? p.buyer ?? p.toTripCode ?? p.tripCode ?? '');
      const quantity = typeof p.acceptedKg === 'number' ? p.acceptedKg : Number(e.batch.weightKg);
      rows.push([
        e.occurredAt.toISOString(), cte, e.eventType, e.batch.code, e.batch.product.code, e.batch.product.name, quantity, 'kg', location,
        String(p.tripCode ?? p.fromTripCode ?? ''), String(p.outcome ?? ''), e.seq, e.hash,
      ]);
    }
    return toCsv(['event_time_utc', 'cte', 'event_type', 'traceability_lot_code', 'product_code', 'product_description', 'quantity', 'unit', 'location', 'reference_trip', 'outcome', 'trace_seq', 'record_hash'], rows);
  }

  /** Scope 3 transport emissions per completed trip (SYN-16): distance × the configured factor. */
  async emissions(fromQ?: string, toQ?: string) {
    const range = parseRange(fromQ, toQ, 366);
    if (typeof range === 'string') throw new AppError('VALIDATION_FAILED', range, HttpStatus.UNPROCESSABLE_ENTITY);
    const factor = await this.config.get('emissionFactorKgPerKm');
    const trips = await this.prisma.trip.findMany({
      where: { status: 'COMPLETED', completedAt: { gte: range.from, lt: range.to } },
      include: { vehicle: { select: { regNo: true } } },
      orderBy: { completedAt: 'asc' },
    });
    const rows = trips.map((t) => ({
      tripCode: t.code, vehicle: t.vehicle.regNo, completedAt: t.completedAt!.toISOString(),
      distanceKm: t.distanceKm === null ? 0 : Number(t.distanceKm), co2Kg: t.co2Kg === null ? 0 : Number(t.co2Kg),
    }));
    const total = (k: 'distanceKm' | 'co2Kg') => Math.round(rows.reduce((a, r) => a + r[k], 0) * 1000) / 1000;
    return {
      from: range.from.toISOString(), to: range.to.toISOString(),
      // Stored per trip at completion; the factor shown is today's value and source.
      currentFactor: factor,
      trips: rows,
      totals: { trips: rows.length, distanceKm: total('distanceKm'), co2Kg: total('co2Kg') },
    };
  }

  emissionsCsv(r: Awaited<ReturnType<ReportsService['emissions']>>): string {
    return toCsv(['trip_code', 'vehicle', 'completed_at_utc', 'distance_km', 'co2_kg'], r.trips.map((t) => [t.tripCode, t.vehicle, t.completedAt, t.distanceKm, t.co2Kg]));
  }

  /** SYN-17: weekly pull-down rates per vehicle, latest first. */
  async reeferHealth() {
    const vehicles = await this.prisma.vehicle.findMany({
      orderBy: { regNo: 'asc' },
      include: { reeferHealth: { orderBy: { periodStart: 'desc' }, take: 8 } },
    });
    return vehicles.map((v) => ({
      vehicleId: v.id,
      regNo: v.regNo,
      baselinePulldownRate: v.baselinePulldownRate,
      flagged: v.reeferHealth[0]?.flagged ?? false,
      weeks: v.reeferHealth.map((h) => ({
        periodStart: h.periodStart.toISOString(), periodEnd: h.periodEnd.toISOString(), pulldownRate: h.pulldownRate, baselineRate: h.baselineRate,
        degradationPct: Math.round(h.degradationPct * 1000) / 10, flagged: h.flagged,
      })),
    }));
  }
}
