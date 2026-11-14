import type { IncidentKind } from '@prisma/client';
import { haversineKm } from '../../common/geo';

/**
 * Pure rules of the incident engine (Section 6.5 "Incident engine", W-2). No I/O, so every
 * branch is unit-tested; the service feeds them data and records the result in the decision log.
 */

export interface TempPoint {
  at: number; // epoch ms
  tempC: number;
}

/** Indicative road ETA without a routing service (same assumptions as D-66): road factor 1.3, 40 km/h. */
export const ROAD_FACTOR = 1.3;
export const AVG_SPEED_KMH = 40;

export function roadKm(a: { lat: number; lng: number }, b: { lat: number; lng: number }): number {
  return haversineKm(a, b) * ROAD_FACTOR;
}

export function roadEtaH(a: { lat: number; lng: number }, b: { lat: number; lng: number }): number {
  return roadKm(a, b) / AVG_SPEED_KMH;
}

/** Least-squares slope of temperature in °C per 10 minutes; null with < 2 points or no time spread. */
export function tempSlopePer10Min(points: TempPoint[]): number | null {
  if (points.length < 2) return null;
  const t0 = points[0].at;
  const xs = points.map((p) => (p.at - t0) / 600_000); // in 10-minute units
  const ys = points.map((p) => p.tempC);
  const n = xs.length;
  const mx = xs.reduce((a, b) => a + b, 0) / n;
  const my = ys.reduce((a, b) => a + b, 0) / n;
  let num = 0;
  let den = 0;
  for (let i = 0; i < n; i++) {
    num += (xs[i] - mx) * (ys[i] - my);
    den += (xs[i] - mx) ** 2;
  }
  return den === 0 ? null : num / den;
}

export type TriggerSource = 'TEMP_ALERT' | 'DRIVER_REPORT' | 'SPOILAGE_GATE' | 'DRIVER_FIX_FAILED';

export interface ClassifyInput {
  source: TriggerSource;
  /** Driver event type for DRIVER_REPORT (INCIDENT_DELAY, INCIDENT_REEFER_FAULT, ...). */
  reportedType?: string;
  /** Latest pod reading; null/undefined = unknown (no packet yet). */
  reeferOn?: boolean | null;
  slopePer10Min?: number | null;
  driftSlopeMax: number;
}

export interface Classification {
  kind: IncidentKind;
  reason: string;
}

/**
 * Step 1 of the engine. Temperature alerts: reefer OFF, or warming faster than `driftSlopeMax`
 * → REEFER_FAILURE; reefer ON and slow drift → TEMP_DRIFT. Driver reports map by type.
 * Returns null for reports that are not incidents of the engine (accident without cargo risk is
 * still treated as a breakdown: the truck cannot continue).
 */
export function classify(i: ClassifyInput): Classification | null {
  switch (i.source) {
    case 'SPOILAGE_GATE':
      return { kind: 'SPOILAGE_RISK', reason: 'remaining shelf life is below remaining ETA + safety margin' };
    case 'DRIVER_FIX_FAILED':
      return { kind: 'SPOILAGE_RISK', reason: 'temperature not recovered after the driver fix window' };
    case 'DRIVER_REPORT':
      switch (i.reportedType) {
        case 'INCIDENT_REEFER_FAULT':
          return { kind: 'REEFER_FAILURE', reason: 'driver reported a reefer fault' };
        case 'INCIDENT_DELAY':
        case 'INCIDENT_ROADBLOCK':
          return { kind: 'DELAY', reason: `driver reported ${i.reportedType === 'INCIDENT_DELAY' ? 'a delay' : 'a road block'}` };
        case 'INCIDENT_BREAKDOWN':
        case 'INCIDENT_ACCIDENT':
          return { kind: 'BREAKDOWN', reason: `driver reported ${i.reportedType === 'INCIDENT_BREAKDOWN' ? 'a breakdown' : 'an accident'}` };
        default:
          return null;
      }
    case 'TEMP_ALERT': {
      const slope = i.slopePer10Min ?? null;
      const slopeText = slope === null ? 'slope unknown' : `slope ${slope.toFixed(2)} °C/10 min (max ${i.driftSlopeMax})`;
      if (i.reeferOn === false) return { kind: 'REEFER_FAILURE', reason: `reefer is OFF; ${slopeText}` };
      if (slope !== null && slope > i.driftSlopeMax) return { kind: 'REEFER_FAILURE', reason: `warming too fast; ${slopeText}` };
      const on = i.reeferOn === true ? 'reefer ON' : 'reefer state unknown';
      return { kind: 'TEMP_DRIFT', reason: `${on}; ${slopeText}` };
    }
  }
}

/** Spoilage decision gate (Section 1.1 step 6). */
export function atSpoilageRisk(remainingShelfLifeH: number, remainingEtaH: number, safetyMarginH: number): boolean {
  return remainingShelfLifeH < remainingEtaH + safetyMarginH;
}

export interface RouteStopPoint {
  id: string;
  lat: number;
  lng: number;
  serviceMin?: number;
}

/** Cumulative indicative ETA (hours from now) to each stop in order, starting at `from`. */
export function cumulativeEtaH(from: { lat: number; lng: number }, stops: RouteStopPoint[], extraDelayH = 0): Map<string, number> {
  const out = new Map<string, number>();
  let at = from;
  let h = extraDelayH;
  for (const s of stops) {
    h += roadEtaH(at, s);
    out.set(s.id, h);
    h += (s.serviceMin ?? 20) / 60;
    at = s;
  }
  return out;
}

/**
 * DELAY (Section 6.5 rule 4): delivery is still feasible when every batch reaches its stop before
 * its shelf life runs out (with the margin). Returns the batches that would not make it.
 */
export function delayInfeasible(
  batches: { batchId: string; stopId: string | null; remainingShelfLifeH: number }[],
  etaByStop: Map<string, number>,
  safetyMarginH: number,
): string[] {
  return batches
    .filter((b) => {
      const eta = b.stopId ? etaByStop.get(b.stopId) : undefined;
      if (eta === undefined) return true; // no stop for this batch any more: cannot be delivered as planned
      return atSpoilageRisk(b.remainingShelfLifeH, eta, safetyMarginH);
    })
    .map((b) => b.batchId);
}

export interface DecisionEntry {
  at: string;
  step: string;
  reason: string;
  inputs?: Record<string, unknown>;
  candidates?: unknown;
  chosen?: unknown;
  by?: string | null;
}

export const entry = (step: string, reason: string, extra: Omit<DecisionEntry, 'at' | 'step' | 'reason'> = {}): DecisionEntry => ({
  at: new Date().toISOString(),
  step,
  reason,
  ...extra,
});
