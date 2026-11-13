import { batchCode, batchCodePrefix, categoryProblems, istYmd, withinEditWindow } from './batch-rules';

describe('batch code', () => {
  it('uses the India calendar day', () => {
    // 20:00 UTC on 13 Nov is 01:30 IST on 14 Nov.
    expect(istYmd(new Date('2026-11-13T20:00:00Z'))).toBe('20261114');
    expect(istYmd(new Date('2026-11-13T10:00:00Z'))).toBe('20261113');
  });

  it('follows {FSH|PRD}-{yyyymmdd}-{site}-{seq4}', () => {
    const at = new Date('2026-11-13T05:00:00Z');
    expect(batchCode(batchCodePrefix('FISH', 'DCK-PTN', at), 1)).toBe('FSH-20261113-DCK-PTN-0001');
    expect(batchCode(batchCodePrefix('PRODUCE', 'FRM-GNG', at), 42)).toBe('PRD-20261113-FRM-GNG-0042');
  });

  it('rejects sequences outside 1..9999', () => {
    expect(() => batchCode('X-', 0)).toThrow(RangeError);
    expect(() => batchCode('X-', 10_000)).toThrow(RangeError);
  });
});

describe('edit window (FO-FR-13)', () => {
  const created = new Date('2026-11-13T10:00:00Z');
  const at = (min: number) => new Date(created.getTime() + min * 60_000);

  it('allows an edit at 29 min', () => {
    expect(withinEditWindow(created, at(29), 30)).toBe(true);
  });

  it('allows an edit at exactly 30 min', () => {
    expect(withinEditWindow(created, at(30), 30)).toBe(true);
  });

  it('refuses an edit at 31 min (→ 409 EDIT_WINDOW_CLOSED)', () => {
    expect(withinEditWindow(created, at(31), 30)).toBe(false);
  });

  it('refuses a time before creation (clock skew / forged)', () => {
    expect(withinEditWindow(created, at(-1), 30)).toBe(false);
  });
});

describe('category field rules', () => {
  const fishOk = { vesselId: 'MH-RTN-1234', iceToFishRatio: 1, initialCoreTemp: 2 };

  it('accepts a complete fish batch', () => {
    expect(categoryProblems('FISH', fishOk)).toEqual([]);
  });

  it('requires vessel, ice ratio and core temp for fish', () => {
    expect(categoryProblems('FISH', {}).map((p) => p.field).sort()).toEqual(['iceToFishRatio', 'initialCoreTemp', 'vesselId']);
  });

  it('enforces fish core temperature −2..+10 °C', () => {
    expect(categoryProblems('FISH', { ...fishOk, initialCoreTemp: 11 })).toEqual([
      { field: 'initialCoreTemp', message: expect.stringContaining('-2 and +10') },
    ]);
    expect(categoryProblems('FISH', { ...fishOk, initialCoreTemp: -2 })).toEqual([]);
  });

  it('rejects produce-only fields on fish and vice versa', () => {
    expect(categoryProblems('FISH', { ...fishOk, brix: 12 }).map((p) => p.field)).toEqual(['brix']);
    expect(categoryProblems('PRODUCE', { farmRef: 'F1', maturityIndex: 3, vesselId: 'V' }).map((p) => p.field)).toEqual(['vesselId']);
  });

  it('requires farm and maturity for produce', () => {
    expect(categoryProblems('PRODUCE', {}).map((p) => p.field).sort()).toEqual(['farmRef', 'maturityIndex']);
  });
});
