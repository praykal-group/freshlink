import { haversineKm } from '../../common/geo';

/** Remaining need of one distribution centre for one product (kg). */
export interface Need {
  siteId: string;
  productId: string;
  lat: number;
  lng: number;
  needKg: number;
}

export interface Available {
  batchId: string;
  productId: string;
  siteId: string;
  lat: number;
  lng: number;
  weightKg: number;
  /** Remaining shelf life; null = not estimated yet (allocated last). */
  shelfLifeH: number | null;
}

export interface Allocation {
  batchId: string;
  productId: string;
  sourceSiteId: string;
  destinationSiteId: string;
  kg: number;
  shelfLifeH: number | null;
}

export const URGENT_SHELF_LIFE_H = 24;

/**
 * FEFO (W-3, Section 6.5): batches with the lowest remaining shelf life are allocated first.
 * A batch with < 24 h left goes to the nearest centre that still needs the product; others go to
 * the centre with the largest remaining need (nearest on a tie). Whole batches only (crates are
 * not split, D-75), so a centre's last batch may exceed its need.
 */
export function allocateFefo(needs: Need[], available: Available[], urgentH = URGENT_SHELF_LIFE_H): Allocation[] {
  const remaining = needs.map((n) => ({ ...n }));
  const order = [...available].sort(
    (a, b) => (a.shelfLifeH ?? Infinity) - (b.shelfLifeH ?? Infinity) || b.weightKg - a.weightKg || a.batchId.localeCompare(b.batchId),
  );
  const out: Allocation[] = [];
  for (const b of order) {
    if (b.shelfLifeH !== null && b.shelfLifeH <= 0) continue; // already spoiled
    const candidates = remaining.filter((n) => n.productId === b.productId && n.needKg > 1e-9);
    if (!candidates.length) continue;
    const dist = (n: Need) => haversineKm(b, n);
    const urgent = b.shelfLifeH !== null && b.shelfLifeH < urgentH;
    const target = candidates.reduce((best, n) =>
      urgent
        ? dist(n) < dist(best) ? n : best
        : n.needKg > best.needKg + 1e-9 || (Math.abs(n.needKg - best.needKg) <= 1e-9 && dist(n) < dist(best)) ? n : best,
    );
    target.needKg -= b.weightKg;
    out.push({ batchId: b.batchId, productId: b.productId, sourceSiteId: b.siteId, destinationSiteId: target.siteId, kg: b.weightKg, shelfLifeH: b.shelfLifeH });
  }
  return out;
}

/** Total need minus what was allocated, floored at 0, per (site, product). */
export function shortfall(needs: Need[], allocations: Allocation[]): Map<string, number> {
  const got = new Map<string, number>();
  for (const a of allocations) got.set(`${a.destinationSiteId}|${a.productId}`, (got.get(`${a.destinationSiteId}|${a.productId}`) ?? 0) + a.kg);
  return new Map(needs.map((n) => [`${n.siteId}|${n.productId}`, Math.max(0, n.needKg - (got.get(`${n.siteId}|${n.productId}`) ?? 0))]));
}
