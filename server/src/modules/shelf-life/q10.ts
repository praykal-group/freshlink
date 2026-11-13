/**
 * Q10 fallback, the same formula as ml/service/app/core/shelf_life.py (Section 8):
 *   remaining = baseShelfLife * Q10 ^ ((refTemp - meanTemp) / 10) - elapsed, clamped >= 0
 * Used only when the ML service cannot be reached, so the spoilage gate always has a value (ML-02).
 */
export const BACKEND_Q10_VERSION = 'backend-q10-1';

export function q10RemainingH(input: { baseShelfLifeH: number; q10: number; refTempC: number; meanTempC: number; hoursSinceHarvest: number }): number {
  const q10 = Math.max(input.q10, 1);
  const total = Math.max(0, input.baseShelfLifeH * q10 ** ((input.refTempC - input.meanTempC) / 10));
  return Math.round(Math.max(0, total - Math.max(0, input.hoursSinceHarvest)) * 100) / 100;
}

/** Reference temperature for a product: middle of its safe range. */
export const refTempOf = (safeMin: number, safeMax: number) => (safeMin + safeMax) / 2;

/** SHELF_LIFE_UPDATED goes into the trace chain only on a change of at least 2 h (Section 6.5). */
export function isSignificantChange(previous: number | null, next: number, thresholdH = 2): boolean {
  return previous === null || Math.abs(next - previous) >= thresholdH;
}
