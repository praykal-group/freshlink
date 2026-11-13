import { z } from 'zod';

const minutes = z.number().int().min(1).max(24 * 60);

/** Every remote-config key and the shape of its value (Section 7 app_config). Unknown keys are rejected. */
export const CONFIG_SCHEMAS = {
  persistMinutes: minutes,
  ackMinutes: minutes,
  offerMinutes: minutes,
  editWindowMin: minutes,
  safetyMarginH: z.number().min(0).max(72),
  driftSlopeMax: z.number().positive().max(10),
  rescueRadiusKm: z.number().positive().max(500),
  gpsIntervalSec: z.number().int().min(5).max(600),
  emissionFactorKgPerKm: z.object({ value: z.number().positive().max(10), source: z.string().min(3).max(300) }),
  featureFlags: z.record(z.string(), z.boolean()),
} as const;

export type ConfigKey = keyof typeof CONFIG_SCHEMAS;
export type ConfigValue<K extends ConfigKey> = z.infer<(typeof CONFIG_SCHEMAS)[K]>;

export const CONFIG_KEYS = Object.keys(CONFIG_SCHEMAS) as ConfigKey[];

export function isConfigKey(key: string): key is ConfigKey {
  return key in CONFIG_SCHEMAS;
}
