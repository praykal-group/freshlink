import type { AlertSeverity, AlertType } from '@prisma/client';

/** Strictest limits across the batches on a truck (Section 6.5). */
export interface Limits {
  tempMin: number;
  tempMax: number;
  humidityMin: number;
  humidityMax: number;
  shockMaxG: number;
  ethyleneMaxPpm: number | null;
  /** Leafy / non-climacteric ethylene-sensitive produce on board → ethylene is CRITICAL. */
  ethyleneSensitiveOnBoard: boolean;
}

export interface ProductLimits {
  safeTempMin: number;
  safeTempMax: number;
  humidityMin: number;
  humidityMax: number;
  shockMaxG: number;
  ethyleneMaxPpm: number | null;
  isClimacteric: boolean;
  isEthyleneSensitive: boolean;
}

export function strictestLimits(products: ProductLimits[]): Limits | null {
  if (!products.length) return null;
  const eth = products.map((p) => p.ethyleneMaxPpm).filter((v): v is number => v !== null);
  return {
    tempMin: Math.max(...products.map((p) => p.safeTempMin)),
    tempMax: Math.min(...products.map((p) => p.safeTempMax)),
    humidityMin: Math.max(...products.map((p) => p.humidityMin)),
    humidityMax: Math.min(...products.map((p) => p.humidityMax)),
    shockMaxG: Math.min(...products.map((p) => p.shockMaxG)),
    ethyleneMaxPpm: eth.length ? Math.min(...eth) : null,
    ethyleneSensitiveOnBoard: products.some((p) => p.isEthyleneSensitive && !p.isClimacteric),
  };
}

/** Per device, kept in Redis between packets. Times are sensor timestamps (ms). */
export interface BreachState {
  tempStart?: number;
  tempAlerted?: boolean;
  humStart?: number;
  humAlerted?: boolean;
  ethAlerted?: boolean;
  lastShockAlertAt?: number;
}

export interface ReadingLite {
  ts: number;
  tempC: number;
  humidityPct: number | null;
  shockG: number | null;
  ethylenePpm: number | null;
}

export type Metric = 'temp' | 'humidity' | 'ethylene' | 'shock';

export type Action =
  | { kind: 'BREACH_START'; metric: Metric; value: number; limit: number }
  | { kind: 'RAISE'; type: AlertType; severity: AlertSeverity; metric: Metric; value: number; limit: number; sinceMs: number }
  | { kind: 'RECOVERED'; metric: Metric; durationMs: number };

export interface EngineConfig {
  /** persistMinutes in real ms (time-scaled in tests). */
  persistMs: number;
  /** At most one SHOCK alert per device per cooldown. */
  shockCooldownMs: number;
}

/**
 * Section 6.5 threshold rules for one reading:
 * - temp/humidity outside limits starts a breach → BREACH_START (shelf-life recompute, SYN-04);
 *   still outside after persistMs → one RAISE (temp CRITICAL, humidity WARNING); back inside → RECOVERED
 * - shock above the product limit → SHOCK WARNING (cooldown)
 * - ethylene above the limit → ETHYLENE WARNING, CRITICAL if sensitive non-climacteric produce is on board
 * One breach never raises twice.
 */
export function evaluate(r: ReadingLite, limits: Limits, prev: BreachState, cfg: EngineConfig): { state: BreachState; actions: Action[] } {
  const s: BreachState = { ...prev };
  const actions: Action[] = [];

  const window = (
    metric: 'temp' | 'humidity',
    value: number | null,
    min: number,
    max: number,
    startKey: 'tempStart' | 'humStart',
    alertedKey: 'tempAlerted' | 'humAlerted',
    type: AlertType,
    severity: AlertSeverity,
  ) => {
    if (value === null) return;
    const outside = value < min || value > max;
    const limit = value > max ? max : min;
    if (outside) {
      if (s[startKey] === undefined) {
        s[startKey] = r.ts;
        actions.push({ kind: 'BREACH_START', metric, value, limit });
      }
      const since = r.ts - (s[startKey] as number);
      if (!s[alertedKey] && since >= cfg.persistMs) {
        s[alertedKey] = true;
        actions.push({ kind: 'RAISE', type, severity, metric, value, limit, sinceMs: since });
      }
    } else if (s[startKey] !== undefined) {
      actions.push({ kind: 'RECOVERED', metric, durationMs: r.ts - (s[startKey] as number) });
      delete s[startKey];
      delete s[alertedKey];
    }
  };

  window('temp', r.tempC, limits.tempMin, limits.tempMax, 'tempStart', 'tempAlerted', 'TEMP_EXCURSION', 'CRITICAL');
  window('humidity', r.humidityPct, limits.humidityMin, limits.humidityMax, 'humStart', 'humAlerted', 'HUMIDITY', 'WARNING');

  if (r.shockG !== null && r.shockG > limits.shockMaxG) {
    if (s.lastShockAlertAt === undefined || r.ts - s.lastShockAlertAt >= cfg.shockCooldownMs) {
      s.lastShockAlertAt = r.ts;
      actions.push({ kind: 'RAISE', type: 'SHOCK', severity: 'WARNING', metric: 'shock', value: r.shockG, limit: limits.shockMaxG, sinceMs: 0 });
    }
  }

  if (limits.ethyleneMaxPpm !== null && r.ethylenePpm !== null) {
    if (r.ethylenePpm > limits.ethyleneMaxPpm) {
      if (!s.ethAlerted) {
        s.ethAlerted = true;
        actions.push({
          kind: 'RAISE',
          type: 'ETHYLENE',
          severity: limits.ethyleneSensitiveOnBoard ? 'CRITICAL' : 'WARNING',
          metric: 'ethylene',
          value: r.ethylenePpm,
          limit: limits.ethyleneMaxPpm,
          sinceMs: 0,
        });
      }
    } else if (s.ethAlerted) {
      delete s.ethAlerted;
      actions.push({ kind: 'RECOVERED', metric: 'ethylene', durationMs: 0 });
    }
  }
  return { state: s, actions };
}

/** Exposure accumulation per batch (Section 9.3 exposure-aggregator). */
export interface Exposure {
  degreeMinutesAbove: number;
  minutesAboveLimit: number;
  tempWeightedSum: number;
  minutesObserved: number;
  maxTemp: number | null;
  shockEvents: number;
  maxEthylenePpm: number | null;
}

export const emptyExposure = (): Exposure => ({
  degreeMinutesAbove: 0, minutesAboveLimit: 0, tempWeightedSum: 0, minutesObserved: 0, maxTemp: null, shockEvents: 0, maxEthylenePpm: null,
});

/** Interval since the device's previous reading, capped at 5 min so a gap is not counted as exposure. */
export const MAX_STEP_MIN = 5;

export function accumulate(e: Exposure, r: ReadingLite, prevTs: number | null, safeTempMax: number, shockMaxG: number): Exposure {
  const dt = prevTs === null ? 1 : Math.min(MAX_STEP_MIN, Math.max(0, (r.ts - prevTs) / 60_000));
  const above = Math.max(0, r.tempC - safeTempMax);
  return {
    degreeMinutesAbove: e.degreeMinutesAbove + above * dt,
    minutesAboveLimit: e.minutesAboveLimit + (above > 0 ? dt : 0),
    tempWeightedSum: e.tempWeightedSum + r.tempC * dt,
    minutesObserved: e.minutesObserved + dt,
    maxTemp: e.maxTemp === null ? r.tempC : Math.max(e.maxTemp, r.tempC),
    shockEvents: e.shockEvents + (r.shockG !== null && r.shockG > shockMaxG ? 1 : 0),
    maxEthylenePpm: r.ethylenePpm === null ? e.maxEthylenePpm : Math.max(e.maxEthylenePpm ?? 0, r.ethylenePpm),
  };
}

export const meanTemp = (e: Exposure) => (e.minutesObserved > 0 ? e.tempWeightedSum / e.minutesObserved : null);
