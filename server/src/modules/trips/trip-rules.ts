import type { TripStatus } from '@prisma/client';

export type TripAction = 'assign' | 'load' | 'preCheck' | 'start' | 'arrive' | 'pod' | 'event' | 'routeResponse';

/** Allowed trip statuses per action. */
export const ALLOWED: Record<TripAction, TripStatus[]> = {
  assign: ['PLANNED', 'ASSIGNED'],
  load: ['PLANNED', 'ASSIGNED', 'PRE_CHECK_DONE'],
  preCheck: ['ASSIGNED', 'PRE_CHECK_DONE'],
  start: ['PRE_CHECK_DONE'],
  arrive: ['IN_PROGRESS'],
  pod: ['IN_PROGRESS'],
  event: ['ASSIGNED', 'PRE_CHECK_DONE', 'IN_PROGRESS'],
  routeResponse: ['ASSIGNED', 'PRE_CHECK_DONE', 'IN_PROGRESS'],
};

export function canDo(status: TripStatus, action: TripAction): boolean {
  return ALLOWED[action].includes(status);
}

export interface Range {
  min: number;
  max: number;
}

/**
 * Setpoint the reefer must hold: the intersection of all loaded products' safe ranges, clipped to
 * what the reefer can do. null = incompatible cargo (no common temperature).
 */
export function allowedSetpoint(productRanges: Range[], reefer: Range): Range | null {
  let lo = reefer.min;
  let hi = reefer.max;
  for (const r of productRanges) {
    lo = Math.max(lo, r.min);
    hi = Math.min(hi, r.max);
  }
  return lo <= hi ? { min: lo, max: hi } : null;
}

export interface PreCheck {
  reeferOn: boolean;
  setpointC: number;
  doorsClosed: boolean;
}

/** DA-FR-03: reefer ON, setpoint inside the allowed range, doors closed. Empty list = pass. */
export function preCheckProblems(check: PreCheck, allowed: Range | null): { code: string; message: string }[] {
  const out: { code: string; message: string }[] = [];
  if (!check.reeferOn) out.push({ code: 'REEFER_OFF', message: 'Switch the reefer on' });
  if (!check.doorsClosed) out.push({ code: 'DOORS_OPEN', message: 'Close and seal the doors' });
  if (allowed === null) {
    out.push({ code: 'INCOMPATIBLE_CARGO', message: 'The loaded products have no common safe temperature' });
  } else if (check.setpointC < allowed.min || check.setpointC > allowed.max) {
    out.push({ code: 'SETPOINT_OUT_OF_RANGE', message: `Set the reefer between ${allowed.min} and ${allowed.max} °C` });
  }
  return out;
}

/** SYN-16: Scope 3 transport emission. The factor and its source are admin config (no default in code). */
export function co2Kg(distanceKm: number, factorKgPerKm: number): number {
  return Math.round(distanceKm * factorKgPerKm * 1000) / 1000;
}

export const mapsLink = (lat: number, lng: number) => `https://maps.google.com/?q=${lat.toFixed(6)},${lng.toFixed(6)}`;

/** Drops that accept any batch on board (no order to match): diversion, cold storage, rescue handover. */
export const OPEN_DROPS: readonly string[] = ['DIVERSION_DROP', 'COLD_STORAGE_DROP', 'RESCUE_DROP'];
