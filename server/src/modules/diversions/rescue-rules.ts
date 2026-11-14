import { roadEtaH, roadKm } from '../incidents/incident-rules';
import { allowedSetpoint } from '../trips/trip-rules';

type Range = { min: number; max: number };

/**
 * RESCUE_PICKUP matching (W-2 b): another IN_PROGRESS truck whose reefer can hold a setpoint safe
 * for its own cargo AND the failing truck's cargo, with free capacity ≥ that cargo, currently within
 * `rescueRadiusKm`, and able to reach it before the cargo spoils. Nearest first. Pure.
 */
export interface RescueCandidateIn {
  tripId: string;
  code: string;
  vehicleId: string;
  reefer: Range;
  capacityKg: number;
  loadKg: number;
  cargoRanges: Range[];
  /** Latest known position; null = unknown (excluded). */
  position: { lat: number; lng: number } | null;
}

export interface RescueNeed {
  failingTripId: string;
  cargoRanges: Range[];
  cargoKg: number;
  at: { lat: number; lng: number };
  radiusKm: number;
  remainingShelfLifeH: number;
  safetyMarginH: number;
}

export type RescueExclusion = 'SAME_TRIP' | 'NO_POSITION' | 'TOO_FAR' | 'NO_CAPACITY' | 'INCOMPATIBLE_TEMPERATURE' | 'NOT_REACHABLE_BEFORE_SPOILAGE';

export interface RescueRanked {
  candidate: RescueCandidateIn;
  distanceKm: number;
  etaH: number;
  setpoint: Range;
}

export function rankRescue(cands: RescueCandidateIn[], need: RescueNeed) {
  const eligible: RescueRanked[] = [];
  const excluded: { tripId: string; code: string; reason: RescueExclusion; detail?: string }[] = [];
  for (const c of cands) {
    const no = (reason: RescueExclusion, detail?: string) => excluded.push({ tripId: c.tripId, code: c.code, reason, ...(detail ? { detail } : {}) });
    if (c.tripId === need.failingTripId) { no('SAME_TRIP'); continue; }
    if (!c.position) { no('NO_POSITION'); continue; }
    const distanceKm = roadKm(c.position, need.at);
    if (distanceKm > need.radiusKm) { no('TOO_FAR', `${distanceKm.toFixed(1)} km > ${need.radiusKm} km`); continue; }
    const free = c.capacityKg - c.loadKg;
    if (free < need.cargoKg) { no('NO_CAPACITY', `free ${free} kg < ${need.cargoKg} kg`); continue; }
    const setpoint = allowedSetpoint([...c.cargoRanges, ...need.cargoRanges], c.reefer);
    if (!setpoint) { no('INCOMPATIBLE_TEMPERATURE'); continue; }
    const etaH = roadEtaH(c.position, need.at);
    if (!(etaH < need.remainingShelfLifeH - need.safetyMarginH)) { no('NOT_REACHABLE_BEFORE_SPOILAGE', `eta ${etaH.toFixed(2)} h`); continue; }
    eligible.push({ candidate: c, distanceKm, etaH, setpoint });
  }
  eligible.sort((a, b) => a.distanceKm - b.distanceKm);
  return { eligible, excluded };
}
