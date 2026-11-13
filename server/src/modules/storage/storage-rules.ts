import type { Grade, ProductCategory, StorageUnitType } from '@prisma/client';

export interface ProductLike {
  category: ProductCategory;
  isClimacteric: boolean;
  safeTempMin: number;
  safeTempMax: number;
}

export interface UnitLike {
  id: string;
  code: string;
  type: StorageUnitType;
  tempMin: number;
  tempMax: number;
  capacityKg: number;
  usedKg: number;
  active: boolean;
}

export interface StoragePathDecision {
  path: StorageUnitType;
  sellFirst: boolean;
  reason: string;
}

/**
 * SYN-10 decision gate (Section 6.5): fish or non-climacteric → blast chiller; climacteric → ripening
 * chamber; grade C overrides both → cold room with a "sell first" flag.
 */
export function decideStoragePath(product: ProductLike, grade: Grade | null): StoragePathDecision {
  if (grade === 'C') {
    return { path: 'COLD_ROOM', sellFirst: true, reason: 'Grade C: hold in a cold room and sell first' };
  }
  if (product.category === 'FISH') {
    return { path: 'BLAST_CHILLER', sellFirst: false, reason: 'Fish: rapid chill in a blast chiller' };
  }
  if (!product.isClimacteric) {
    return { path: 'BLAST_CHILLER', sellFirst: false, reason: 'Non-climacteric produce: pre-cool in a blast chiller' };
  }
  return { path: 'RIPENING_CHAMBER', sellFirst: false, reason: 'Climacteric produce: ethylene-controlled ripening chamber' };
}

/** A unit fits when it can hold a temperature inside the product's safe range. */
export function tempFits(unit: Pick<UnitLike, 'tempMin' | 'tempMax'>, product: ProductLike): boolean {
  return unit.tempMin <= product.safeTempMax && unit.tempMax >= product.safeTempMin;
}

export const freeKg = (u: UnitLike) => u.capacityKg - u.usedKg;

/**
 * SYN-20: candidate units of the decided type at the batch's site with enough free capacity and a
 * fitting temperature range. Best fit first (least free space that still holds the batch) to keep
 * large units free for large batches.
 */
export function rankUnits(units: UnitLike[], product: ProductLike, path: StorageUnitType, weightKg: number): UnitLike[] {
  return units
    .filter((u) => u.active && u.type === path && freeKg(u) >= weightKg && tempFits(u, product))
    .sort((a, b) => freeKg(a) - freeKg(b) || a.code.localeCompare(b.code));
}
