import type { BuyerType, Grade } from '@prisma/client';
import { z } from 'zod';
import { roadEtaH, roadKm } from '../incidents/incident-rules';

/**
 * Backup-buyer candidate filtering and ranking (W-1, Section 6.5 "Diversion offers"). Pure.
 * A buyer qualifies when it is active, accepts every product in the cargo, accepts the grade, is
 * open when the truck would arrive, has room, and the truck gets there before the cargo spoils.
 */

export const WEEKDAYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'] as const;
const HHMM = /^([01]\d|2[0-3]):[0-5]\d$/;

/** `{"mon": [["06:00","20:00"]], ...}`; a range whose end is before its start runs past midnight. */
export const openingHoursSchema = z
  .object(Object.fromEntries(WEEKDAYS.map((d) => [d, z.array(z.tuple([z.string().regex(HHMM), z.string().regex(HHMM)])).max(4).optional()])))
  .strict();
export type OpeningHours = Partial<Record<(typeof WEEKDAYS)[number], [string, string][]>>;

const IST_OFFSET_MS = 5.5 * 3_600_000;
const toMin = (hhmm: string) => Number(hhmm.slice(0, 2)) * 60 + Number(hhmm.slice(3, 5));

/** Is the buyer open at `at` (evaluated in IST)? "23:59" as an end counts as end of day. */
export function isOpenAt(hours: OpeningHours, at: Date): boolean {
  const ist = new Date(at.getTime() + IST_OFFSET_MS);
  const day = ist.getUTCDay();
  const minute = ist.getUTCHours() * 60 + ist.getUTCMinutes();
  const inRange = (ranges: [string, string][] | undefined, test: (s: number, e: number) => boolean) => (ranges ?? []).some(([s, e]) => test(toMin(s), toMin(e) === 1439 ? 1440 : toMin(e)));
  // Today's ranges, and yesterday's ranges that run past midnight.
  if (inRange(hours[WEEKDAYS[day]], (s, e) => (s <= e ? minute >= s && minute < e : minute >= s))) return true;
  return inRange(hours[WEEKDAYS[(day + 6) % 7]], (s, e) => s > e && minute < e);
}

export const GRADE_RANK: Record<Grade, number> = { A: 3, B: 2, C: 1 };

/** `minGrade ≤ batch grade` (A best). Ungraded cargo counts as C, the lowest (D-102). */
export function gradeAccepted(minGrade: Grade, grade: Grade | null): boolean {
  return GRADE_RANK[grade ?? 'C'] >= GRADE_RANK[minGrade];
}

export interface BuyerIn {
  id: string;
  name: string;
  type: BuyerType;
  lat: number;
  lng: number;
  acceptedProductIds: string[];
  minGrade: Grade;
  discountPct: number;
  openingHours: OpeningHours;
  capacityKg: number | null;
  active: boolean;
}

export interface CargoIn {
  productIds: string[];
  /** Worst grade on board (null = ungraded). */
  grade: Grade | null;
  quantityKg: number;
  /** Lowest remaining shelf life among the diverted batches, hours from now. */
  remainingShelfLifeH: number;
  from: { lat: number; lng: number };
  now: Date;
  safetyMarginH: number;
}

export type ExclusionReason = 'INACTIVE' | 'ALREADY_OFFERED' | 'WRONG_TYPE' | 'PRODUCT_NOT_ACCEPTED' | 'GRADE_TOO_LOW' | 'CLOSED_AT_ETA' | 'NO_CAPACITY' | 'NOT_REACHABLE_BEFORE_SPOILAGE';

export interface RankedBuyer {
  buyer: BuyerIn;
  distanceKm: number;
  etaH: number;
  arriveAt: Date;
}

export interface RankResult {
  eligible: RankedBuyer[];
  excluded: { buyerId: string; name: string; reason: ExclusionReason; detail?: string }[];
}

export interface RankOptions {
  types?: BuyerType[];
  excludeIds?: Set<string>;
  /** DISCOUNT: `(discountPct asc, etaH asc)` (W-1). NEAREST: `(etaH asc)` for cold storage (W-2 a). */
  sort: 'DISCOUNT' | 'NEAREST';
}

export function rankBuyers(buyers: BuyerIn[], cargo: CargoIn, opts: RankOptions): RankResult {
  const out: RankResult = { eligible: [], excluded: [] };
  for (const b of buyers) {
    const no = (reason: ExclusionReason, detail?: string) => out.excluded.push({ buyerId: b.id, name: b.name, reason, ...(detail ? { detail } : {}) });
    if (!b.active) { no('INACTIVE'); continue; }
    if (opts.excludeIds?.has(b.id)) { no('ALREADY_OFFERED'); continue; }
    if (opts.types && !opts.types.includes(b.type)) { no('WRONG_TYPE', b.type); continue; }
    const missing = cargo.productIds.filter((p) => !b.acceptedProductIds.includes(p));
    if (missing.length) { no('PRODUCT_NOT_ACCEPTED', missing.join(',')); continue; }
    if (!gradeAccepted(b.minGrade, cargo.grade)) { no('GRADE_TOO_LOW', `min ${b.minGrade}, cargo ${cargo.grade ?? 'ungraded'}`); continue; }
    if (b.capacityKg !== null && b.capacityKg < cargo.quantityKg) { no('NO_CAPACITY', `${b.capacityKg} < ${cargo.quantityKg} kg`); continue; }
    const etaH = roadEtaH(cargo.from, b);
    const arriveAt = new Date(cargo.now.getTime() + etaH * 3_600_000);
    if (!isOpenAt(b.openingHours, arriveAt)) { no('CLOSED_AT_ETA', arriveAt.toISOString()); continue; }
    // "ETA < shelf life − margin"
    if (!(etaH < cargo.remainingShelfLifeH - cargo.safetyMarginH)) {
      no('NOT_REACHABLE_BEFORE_SPOILAGE', `eta ${etaH.toFixed(2)} h, shelf ${cargo.remainingShelfLifeH.toFixed(2)} h, margin ${cargo.safetyMarginH} h`);
      continue;
    }
    out.eligible.push({ buyer: b, distanceKm: roadKm(cargo.from, b), etaH, arriveAt });
  }
  out.eligible.sort((x, y) =>
    opts.sort === 'NEAREST' ? x.etaH - y.etaH : x.buyer.discountPct - y.buyer.discountPct || x.etaH - y.etaH,
  );
  return out;
}
