import { HttpStatus, Inject, Injectable, Optional } from '@nestjs/common';
import type Redis from 'ioredis';
import { AppError } from '../../common/errors/app-error';
import { InfluxService, Point } from '../../infra/influx/influx.service';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { REDIS } from '../../infra/redis/redis.module';
import { RealtimeService } from '../realtime/realtime.service';
import { REDIS_KEYS, type TelemetryMessage } from './telemetry-message';
import { strictestLimits } from './thresholds';

export const WINDOWS = ['1m', '5m', '15m', '1h'] as const;
export type Window = (typeof WINDOWS)[number];
const MAX_RANGE_MS = 31 * 86_400_000;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export interface GpsPoint {
  lat: number;
  lng: number;
  speedKmh?: number;
  accuracyM?: number;
  at: string;
}

/**
 * Reads for the API (manager chart, driver cargo strip) and phone GPS writes (DA-FR-10).
 * Flux has no bind parameters: every interpolated value is validated (UUID, ISO date, whitelist).
 */
@Injectable()
export class TelemetryService {
  constructor(
    private readonly influx: InfluxService,
    private readonly prisma: PrismaService,
    private readonly realtime: RealtimeService,
    @Optional() @Inject(REDIS) private readonly redis?: Redis,
  ) {}

  /** GET /trips/:id/telemetry: mean per window (shock: max) + the safe band of the cargo. */
  async tripSeries(tripId: string, from: Date, to: Date, every: Window) {
    if (!UUID.test(tripId)) throw new AppError('INVALID_ID', 'Invalid trip id');
    if (!(from < to)) throw new AppError('INVALID_RANGE', 'from must be before to');
    if (to.getTime() - from.getTime() > MAX_RANGE_MS) throw new AppError('RANGE_TOO_LONG', 'At most 31 days');
    if (!this.influx.configured) throw new AppError('TELEMETRY_UNAVAILABLE', 'InfluxDB is not configured', HttpStatus.SERVICE_UNAVAILABLE);
    const base = `from(bucket: "${this.influx.bucket}")
  |> range(start: ${from.toISOString()}, stop: ${to.toISOString()})
  |> filter(fn: (r) => r._measurement == "reefer" and r.trip_id == "${tripId}")`;
    const mean = `${base}
  |> filter(fn: (r) => r._field == "temp_c" or r._field == "humidity_pct" or r._field == "ethylene_ppm")
  |> aggregateWindow(every: ${every}, fn: mean, createEmpty: false)`;
    const shock = `${base}
  |> filter(fn: (r) => r._field == "shock_g")
  |> aggregateWindow(every: ${every}, fn: max, createEmpty: false)`;
    const [rows, shocks] = await Promise.all([
      this.influx.query<{ _time: string; _field: string; _value: number }>(mean),
      this.influx.query<{ _time: string; _value: number }>(shock),
    ]);
    const byTime = new Map<string, Record<string, number | string>>();
    for (const r of rows) byTime.set(r._time, { ...(byTime.get(r._time) ?? { at: r._time }), [r._field]: round(r._value) });
    for (const r of shocks) byTime.set(r._time, { ...(byTime.get(r._time) ?? { at: r._time }), shock_g: round(r._value) });

    const cargo = await this.prisma.tripBatch.findMany({ where: { tripId }, select: { batch: { select: { product: true } } } });
    const band = strictestLimits(
      cargo.map(({ batch: { product: p } }) => ({
        safeTempMin: Number(p.safeTempMin), safeTempMax: Number(p.safeTempMax), humidityMin: Number(p.humidityMin), humidityMax: Number(p.humidityMax),
        shockMaxG: Number(p.shockMaxG), ethyleneMaxPpm: p.ethyleneMaxPpm === null ? null : Number(p.ethyleneMaxPpm), isClimacteric: p.isClimacteric, isEthyleneSensitive: p.isEthyleneSensitive,
      })),
    );
    return { tripId, from, to, every, band, points: [...byTime.values()].sort((a, b) => String(a.at).localeCompare(String(b.at))) };
  }

  /** Latest pod reading for a vehicle (Redis, written by the telemetry writer). */
  async lastReading(vehicleId: string): Promise<TelemetryMessage | null> {
    if (!this.redis) return null;
    const raw = await this.redis.get(REDIS_KEYS.lastReading(vehicleId)).catch(() => null);
    return raw ? (JSON.parse(raw) as TelemetryMessage) : null;
  }

  /** Phone GPS (DA-FR-10) → InfluxDB `driver_gps`; the newest point also goes to the live map. */
  async writeGps(tripId: string, driverId: string, points: GpsPoint[]) {
    if (!points.length) return { written: 0 };
    if (!this.influx.configured) throw new AppError('TELEMETRY_UNAVAILABLE', 'InfluxDB is not configured', HttpStatus.SERVICE_UNAVAILABLE);
    const pts = points.map((g) => {
      const p = new Point('driver_gps').tag('trip_id', tripId).tag('driver_id', driverId).floatField('lat', g.lat).floatField('lng', g.lng).timestamp(new Date(g.at));
      if (g.speedKmh !== undefined) p.floatField('speed_kmh', g.speedKmh);
      if (g.accuracyM !== undefined) p.floatField('accuracy_m', g.accuracyM);
      return p;
    });
    await this.influx.writeNow(pts);
    const last = [...points].sort((a, b) => a.at.localeCompare(b.at)).at(-1) as GpsPoint;
    this.realtime.toManagers('vehicle.position', { tripId, source: 'phone', lat: last.lat, lng: last.lng, speedKmh: last.speedKmh ?? null, at: last.at });
    return { written: pts.length };
  }
}

const round = (v: number) => (typeof v === 'number' ? Math.round(v * 100) / 100 : v);
