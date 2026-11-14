import type { Reading } from './packet';

/** Kafka `truck-telemetry` value: a decoded reading plus the context the bridge attached. */
export interface TelemetryMessage {
  deviceCode: string;
  vehicleId: string | null;
  tripId: string | null;
  ts: string; // sensor time, ISO
  receivedAt: string; // bridge time, ISO
  seq: number | null;
  tempC: number;
  humidityPct: number | null;
  ax: number | null;
  ay: number | null;
  az: number | null;
  shockG: number | null;
  ethylenePpm: number | null;
  lat: number | null;
  lng: number | null;
  reeferOn: boolean | null;
  setpointC: number | null;
  doorOpen: boolean | null;
  batteryPct: number | null;
  format: Reading['format'];
}

export function toMessage(r: Reading, ctx: { vehicleId: string | null; tripId: string | null }, receivedAt: Date): TelemetryMessage {
  return { ...r, ts: r.ts.toISOString(), receivedAt: receivedAt.toISOString(), vehicleId: ctx.vehicleId, tripId: ctx.tripId };
}

export const REDIS_KEYS = {
  lastSeen: 'telemetry:lastseen', // hash deviceCode → epoch ms
  offline: 'telemetry:offline', // set of deviceCodes with an open offline alert
  lastReading: (vehicleId: string) => `telemetry:last:${vehicleId}`,
  breach: (deviceCode: string) => `telemetry:breach:${deviceCode}`,
  exposure: (batchId: string) => `telemetry:exposure:${batchId}`,
  exposureDirty: 'telemetry:exposure:dirty',
  prevTs: 'telemetry:prevts', // hash deviceCode → last sensor ts (ms)
  /** now − packet ts. Packet time is whole seconds, so this carries 0–999 ms of rounding. */
  latencyWrite: 'metrics:latency:sensor_to_influx_ms',
  /** now − bridge receipt, millisecond-accurate (the server-side part of SRV-02). */
  latencyBridgeWrite: 'metrics:latency:bridge_to_influx_ms',
  latencyShelf: 'metrics:latency:breach_to_shelf_life_ms',
  counter: (name: string) => `metrics:telemetry:${name}`,
};
