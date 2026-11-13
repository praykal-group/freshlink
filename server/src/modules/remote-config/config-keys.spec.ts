import { RateLimiter } from '../../common/cache/ttl-cache';
import { CONFIG_SCHEMAS, isConfigKey } from './config-keys';

describe('remote config schemas', () => {
  it('accepts the seeded defaults', () => {
    const seeded: Record<string, unknown> = {
      persistMinutes: 15,
      ackMinutes: 5,
      offerMinutes: 10,
      safetyMarginH: 2,
      driftSlopeMax: 0.5,
      rescueRadiusKm: 30,
      emissionFactorKgPerKm: { value: 0.9, source: 'PLACEHOLDER - replace with sourced factor' },
      gpsIntervalSec: 30,
      editWindowMin: 30,
      featureFlags: {},
    };
    for (const [k, v] of Object.entries(seeded)) {
      expect(isConfigKey(k)).toBe(true);
      if (isConfigKey(k)) expect(CONFIG_SCHEMAS[k].safeParse(v).success).toBe(true);
    }
  });

  it('rejects bad values', () => {
    expect(CONFIG_SCHEMAS.persistMinutes.safeParse(0).success).toBe(false);
    expect(CONFIG_SCHEMAS.persistMinutes.safeParse('15').success).toBe(false);
    expect(CONFIG_SCHEMAS.emissionFactorKgPerKm.safeParse(0.9).success).toBe(false); // source is mandatory (SYN-16)
    expect(CONFIG_SCHEMAS.featureFlags.safeParse({ beta: 'yes' }).success).toBe(false);
  });

  it('knows only declared keys', () => {
    expect(isConfigKey('dropTables')).toBe(false);
  });
});

describe('RateLimiter (hook: 5/hour/phone)', () => {
  it('allows 5 then blocks until the window resets', () => {
    const rl = new RateLimiter(5, 3_600_000);
    const t0 = 1_000_000;
    for (let i = 0; i < 5; i++) expect(rl.hit('+91999', t0 + i)).toBe(true);
    expect(rl.hit('+91999', t0 + 10)).toBe(false);
    expect(rl.hit('+91888', t0 + 10)).toBe(true); // other phone unaffected
    expect(rl.hit('+91999', t0 + 3_600_001)).toBe(true);
  });
});
