import { decideStoragePath, type ProductLike, rankUnits, type UnitLike } from './storage-rules';

// M4: storage path rules for fish / banana / spinach (SYN-10) + unit recommendation (SYN-20).
const fish: ProductLike = { category: 'FISH', isClimacteric: false, safeTempMin: 0, safeTempMax: 4 };
const banana: ProductLike = { category: 'PRODUCE', isClimacteric: true, safeTempMin: 13, safeTempMax: 15 };
const spinach: ProductLike = { category: 'PRODUCE', isClimacteric: false, safeTempMin: 0, safeTempMax: 2 };

const unit = (over: Partial<UnitLike>): UnitLike => ({
  id: over.code ?? 'u',
  code: 'U',
  type: 'BLAST_CHILLER',
  tempMin: -1,
  tempMax: 2,
  capacityKg: 1000,
  usedKg: 0,
  active: true,
  ...over,
});

describe('decideStoragePath', () => {
  it('fish → blast chiller', () => {
    expect(decideStoragePath(fish, null).path).toBe('BLAST_CHILLER');
  });

  it('banana (climacteric) → ripening chamber', () => {
    expect(decideStoragePath(banana, 'A').path).toBe('RIPENING_CHAMBER');
  });

  it('spinach (non-climacteric produce) → blast chiller', () => {
    expect(decideStoragePath(spinach, 'B').path).toBe('BLAST_CHILLER');
  });

  it('grade C → cold room with sell-first, for any product', () => {
    for (const p of [fish, banana, spinach]) {
      expect(decideStoragePath(p, 'C')).toMatchObject({ path: 'COLD_ROOM', sellFirst: true });
    }
  });
});

describe('rankUnits', () => {
  const units = [
    unit({ code: 'BC-BIG', capacityKg: 5000, usedKg: 0 }),
    unit({ code: 'BC-SMALL', capacityKg: 600, usedKg: 400 }), // 200 free
    unit({ code: 'BC-TIGHT', capacityKg: 600, usedKg: 500 }), // 100 free
    unit({ code: 'BC-OFF', active: false }),
    unit({ code: 'RC-1', type: 'RIPENING_CHAMBER', tempMin: 12, tempMax: 18 }),
    unit({ code: 'BC-WARM', tempMin: 8, tempMax: 12 }), // does not reach fish range
  ];

  it('keeps only active units of the right type, with room and a fitting temperature; best fit first', () => {
    expect(rankUnits(units, fish, 'BLAST_CHILLER', 150).map((u) => u.code)).toEqual(['BC-SMALL', 'BC-BIG']);
  });

  it('returns nothing when no unit has room', () => {
    expect(rankUnits(units, fish, 'BLAST_CHILLER', 10_000)).toEqual([]);
  });

  it('matches banana to the ripening chamber only', () => {
    expect(rankUnits(units, banana, 'RIPENING_CHAMBER', 100).map((u) => u.code)).toEqual(['RC-1']);
  });
});
