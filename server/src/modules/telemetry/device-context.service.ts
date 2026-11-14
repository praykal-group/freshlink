import { Injectable } from '@nestjs/common';
import { TtlCache } from '../../common/cache/ttl-cache';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { type Limits, type ProductLimits, strictestLimits } from './thresholds';

export interface DeviceInfo {
  deviceCode: string;
  vehicleId: string | null;
}

export interface CargoBatch {
  batchId: string;
  safeTempMax: number;
  shockMaxG: number;
}

export interface TripCargo {
  tripId: string;
  vehicleId: string;
  driverId: string | null;
  code: string;
  limits: Limits | null;
  batches: CargoBatch[];
}

/**
 * Lookups the pipeline needs per packet, cached briefly in-process (packets arrive every 60 s per
 * device, so a 30 s cache cuts DB reads without delaying trip/load changes noticeably).
 */
@Injectable()
export class DeviceContextService {
  private readonly devices = new TtlCache<DeviceInfo | null>(60_000);
  private readonly trips = new TtlCache<string | null>(30_000);
  private readonly cargo = new TtlCache<TripCargo | null>(30_000);

  constructor(private readonly prisma: PrismaService) {}

  /** MQTT username (topic segment) → device. Unknown devices return null. */
  async device(username: string): Promise<DeviceInfo | null> {
    const hit = this.devices.get(username);
    if (hit !== undefined) return hit;
    const d = await this.prisma.iotDevice.findUnique({ where: { mqttUsername: username }, select: { deviceCode: true, vehicleId: true, status: true } });
    const info = d && d.status === 'ACTIVE' ? { deviceCode: d.deviceCode, vehicleId: d.vehicleId } : null;
    this.devices.set(username, info);
    return info;
  }

  async activeTripId(vehicleId: string): Promise<string | null> {
    const hit = this.trips.get(vehicleId);
    if (hit !== undefined) return hit;
    const t = await this.prisma.trip.findFirst({ where: { vehicleId, status: 'IN_PROGRESS' }, select: { id: true } });
    this.trips.set(vehicleId, t?.id ?? null);
    return t?.id ?? null;
  }

  async tripCargo(tripId: string): Promise<TripCargo | null> {
    const hit = this.cargo.get(tripId);
    if (hit !== undefined) return hit;
    const trip = await this.prisma.trip.findUnique({
      where: { id: tripId },
      select: {
        id: true, code: true, vehicleId: true, driverId: true, status: true,
        batches: { where: { unloadedAt: null }, select: { batch: { select: { id: true, product: true } } } },
      },
    });
    if (!trip || trip.status !== 'IN_PROGRESS') {
      this.cargo.set(tripId, null);
      return null;
    }
    const products: ProductLimits[] = trip.batches.map(({ batch: { product: p } }) => ({
      safeTempMin: Number(p.safeTempMin), safeTempMax: Number(p.safeTempMax), humidityMin: Number(p.humidityMin), humidityMax: Number(p.humidityMax),
      shockMaxG: Number(p.shockMaxG), ethyleneMaxPpm: p.ethyleneMaxPpm === null ? null : Number(p.ethyleneMaxPpm),
      isClimacteric: p.isClimacteric, isEthyleneSensitive: p.isEthyleneSensitive,
    }));
    const value: TripCargo = {
      tripId: trip.id,
      code: trip.code,
      vehicleId: trip.vehicleId,
      driverId: trip.driverId,
      limits: strictestLimits(products),
      batches: trip.batches.map(({ batch }) => ({ batchId: batch.id, safeTempMax: Number(batch.product.safeTempMax), shockMaxG: Number(batch.product.shockMaxG) })),
    };
    this.cargo.set(tripId, value);
    return value;
  }
}
