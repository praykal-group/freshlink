import { allocateFefo, type Available, type Need, shortfall } from './fefo';

// M7: FEFO picks the lowest shelf life first (W-3, Section 6.5).
const CSN = { lat: 19.8762, lng: 75.3433 }; // Chh. Sambhajinagar DC
const JLN = { lat: 19.8347, lng: 75.8816 }; // Jalna DC (~57 km east)
const PAITHAN = { lat: 19.4769, lng: 75.3859 }; // dock, nearer to CSN

const need = (siteId: string, at: { lat: number; lng: number }, needKg: number, productId = 'ROHU'): Need => ({ siteId, productId, needKg, ...at });
const batch = (batchId: string, shelfLifeH: number | null, weightKg = 100, at = PAITHAN, productId = 'ROHU'): Available => ({
  batchId, productId, siteId: 'dock', weightKg, shelfLifeH, ...at,
});

describe('allocateFefo', () => {
  it('allocates the lowest remaining shelf life first', () => {
    const out = allocateFefo([need('CSN', CSN, 250)], [batch('long', 120), batch('short', 40), batch('mid', 80), batch('none', null)]);
    expect(out.map((a) => a.batchId)).toEqual(['short', 'mid', 'long']); // 'none' (no estimate) is last and not needed
  });

  it('sends batches with < 24 h left to the nearest centre that needs the product', () => {
    const out = allocateFefo([need('CSN', CSN, 100), need('JLN', JLN, 500)], [batch('urgent', 10)]);
    expect(out[0].destinationSiteId).toBe('CSN'); // nearer, although JLN needs more
  });

  it('sends other batches to the centre with the largest remaining need', () => {
    const out = allocateFefo([need('CSN', CSN, 100), need('JLN', JLN, 500)], [batch('a', 60), batch('b', 70)]);
    expect(out.map((a) => a.destinationSiteId)).toEqual(['JLN', 'JLN']);
  });

  it('allocates whole batches only and stops once the need is covered', () => {
    const out = allocateFefo([need('CSN', CSN, 150)], [batch('a', 30, 100), batch('b', 40, 100), batch('c', 50, 100)]);
    expect(out.map((a) => [a.batchId, a.kg])).toEqual([['a', 100], ['b', 100]]); // 200 ≥ 150, c untouched
  });

  it('skips spoiled batches and other products', () => {
    const out = allocateFefo([need('CSN', CSN, 500)], [batch('spoiled', 0), batch('banana', 50, 100, PAITHAN, 'BANANA'), batch('ok', 60)]);
    expect(out.map((a) => a.batchId)).toEqual(['ok']);
  });

  it('reports the shortfall per centre and product', () => {
    const needs = [need('CSN', CSN, 350)];
    const out = allocateFefo(needs, [batch('a', 30, 100), batch('b', 40, 100)]);
    expect(shortfall(needs, out).get('CSN|ROHU')).toBe(150);
  });
});
