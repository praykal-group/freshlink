import { accumulate, type BreachState, emptyExposure, evaluate, type Limits, meanTemp, strictestLimits } from './thresholds';

// M8 / Section 6.5: persistence window, one alert per breach, shock, ethylene, exposure.
const fish = { safeTempMin: 0, safeTempMax: 4, humidityMin: 85, humidityMax: 98, shockMaxG: 3, ethyleneMaxPpm: null, isClimacteric: false, isEthyleneSensitive: false };
const banana = { safeTempMin: 13, safeTempMax: 15, humidityMin: 90, humidityMax: 95, shockMaxG: 2, ethyleneMaxPpm: 1, isClimacteric: true, isEthyleneSensitive: true };
const spinach = { safeTempMin: 0, safeTempMax: 2, humidityMin: 95, humidityMax: 100, shockMaxG: 3, ethyleneMaxPpm: 0.1, isClimacteric: false, isEthyleneSensitive: true };

const MIN = 60_000;
const cfg = { persistMs: 15 * MIN, shockCooldownMs: 10 * MIN };
const limits = strictestLimits([fish]) as Limits;
const at = (m: number) => Date.UTC(2026, 10, 14, 5, 0) + m * MIN;
const r = (m: number, tempC: number, extra: Partial<{ humidityPct: number; shockG: number; ethylenePpm: number }> = {}) => ({
  ts: at(m), tempC, humidityPct: extra.humidityPct ?? 90, shockG: extra.shockG ?? 0.2, ethylenePpm: extra.ethylenePpm ?? null,
});

/** Feed readings through the engine like the consumer does. */
function run(readings: ReturnType<typeof r>[], lim: Limits = limits, state: BreachState = {}) {
  const all = [];
  for (const x of readings) {
    const out = evaluate(x, lim, state, cfg);
    state = out.state;
    all.push(...out.actions);
  }
  return { actions: all, state };
}

describe('strictestLimits', () => {
  it('intersects ranges and takes the lowest shock / ethylene limits', () => {
    expect(strictestLimits([fish, spinach])).toEqual({
      tempMin: 0, tempMax: 2, humidityMin: 95, humidityMax: 98, shockMaxG: 3, ethyleneMaxPpm: 0.1, ethyleneSensitiveOnBoard: true,
    });
    expect(strictestLimits([])).toBeNull();
  });

  it('bananas alone are ethylene-sensitive but climacteric → not a CRITICAL ethylene cargo', () => {
    expect(strictestLimits([banana])?.ethyleneSensitiveOnBoard).toBe(false);
  });
});

describe('temperature breach', () => {
  it('starts a breach immediately (shelf-life recompute) and alerts once after the persistence window', () => {
    const { actions } = run([r(0, 3), r(1, 5), r(2, 5.5), r(10, 6), r(16, 6.2), r(17, 6.4), r(30, 7)]);
    expect(actions.map((a) => a.kind)).toEqual(['BREACH_START', 'RAISE']);
    expect(actions[0]).toMatchObject({ metric: 'temp', value: 5, limit: 4 });
    expect(actions[1]).toMatchObject({ type: 'TEMP_EXCURSION', severity: 'CRITICAL', sinceMs: 15 * MIN });
  });

  it('no alert if it recovers inside the window; a new breach starts fresh', () => {
    const { actions } = run([r(0, 5), r(10, 5), r(14, 3), r(20, 5), r(36, 5)]);
    expect(actions.map((a) => `${a.kind}:${a.metric}`)).toEqual(['BREACH_START:temp', 'RECOVERED:temp', 'BREACH_START:temp', 'RAISE:temp']);
  });

  it('a breach below the minimum counts too', () => {
    expect(run([r(0, -1)]).actions[0]).toMatchObject({ kind: 'BREACH_START', limit: 0 });
  });

  it('uses sensor time: a burst replay of a 20-min excursion still raises', () => {
    const replay = [0, 5, 10, 15, 20].map((m) => r(m, 8)); // all arriving in the same second
    expect(run(replay).actions.filter((a) => a.kind === 'RAISE')).toHaveLength(1);
  });
});

describe('other metrics', () => {
  it('humidity breach → WARNING after the window', () => {
    const { actions } = run([r(0, 3, { humidityPct: 60 }), r(16, 3, { humidityPct: 60 })]);
    expect(actions.find((a) => a.kind === 'RAISE')).toMatchObject({ type: 'HUMIDITY', severity: 'WARNING' });
  });

  it('shock above the limit → WARNING, then a cooldown', () => {
    const { actions } = run([r(0, 3, { shockG: 4.5 }), r(2, 3, { shockG: 6 }), r(12, 3, { shockG: 5 })]);
    expect(actions.filter((a) => a.kind === 'RAISE').map((a) => (a as { value: number }).value)).toEqual([4.5, 5]);
  });

  it('ethylene: WARNING with only climacteric cargo, CRITICAL when leafy produce shares the truck; once per build-up', () => {
    const bananas = strictestLimits([banana]) as Limits;
    const mixed = strictestLimits([banana, spinach]) as Limits;
    const high = (m: number) => ({ ...r(m, 14), ethylenePpm: 1.5 });
    expect(run([high(0), high(1)], bananas).actions.filter((a) => a.kind === 'RAISE')).toEqual([expect.objectContaining({ type: 'ETHYLENE', severity: 'WARNING' })]);
    expect(run([high(0)], mixed).actions.find((a) => a.kind === 'RAISE')).toMatchObject({ severity: 'CRITICAL' });
  });
});

describe('exposure accumulation', () => {
  it('degree-minutes above the limit, minutes above, mean/max, shocks, peak ethylene', () => {
    let e = emptyExposure();
    e = accumulate(e, r(0, 3), null, 4, 3); // first reading counts as 1 min
    e = accumulate(e, { ...r(1, 6), shockG: 4 }, at(0), 4, 3); // 1 min at 2 °C above
    e = accumulate(e, { ...r(2, 7), ethylenePpm: 0.8 }, at(1), 4, 3); // 1 min at 3 °C above
    expect(e).toMatchObject({ degreeMinutesAbove: 5, minutesAboveLimit: 2, maxTemp: 7, shockEvents: 1, maxEthylenePpm: 0.8 });
    expect(meanTemp(e)).toBeCloseTo((3 + 6 + 7) / 3);
  });

  it('caps a gap at 5 minutes so an outage is not counted as exposure', () => {
    const e = accumulate(emptyExposure(), r(60, 9), at(0), 4, 3);
    expect(e.degreeMinutesAbove).toBe(25); // 5 °C × 5 min, not × 60
  });
});
