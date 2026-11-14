import type { TempPoint } from '../incidents/incident-rules';

/**
 * Predictive reefer maintenance (SYN-17, Section 6.5): pull-down rate in °C/min during the first
 * 20 min after a trip start or a door-close, per vehicle per week. Degradation vs the baseline
 * (median of the first 4 weeks) above 30 % → REEFER_MAINTENANCE. Pure.
 */
export const PULLDOWN_WINDOW_MIN = 20;
export const DEGRADATION_LIMIT = 0.3;
export const BASELINE_WEEKS = 4;
/** A window only counts when the box actually cooled (≥ 0.5 °C) over ≥ 5 readings. */
const MIN_DROP_C = 0.5;
const MIN_POINTS = 5;

/** Cooling rate (positive °C/min) in the window after `start`; null if there was no real pull-down. */
export function pulldownRate(points: TempPoint[], start: number, windowMin = PULLDOWN_WINDOW_MIN): number | null {
  const w = points.filter((p) => p.at >= start && p.at <= start + windowMin * 60_000).sort((a, b) => a.at - b.at);
  if (w.length < MIN_POINTS) return null;
  const drop = w[0].tempC - Math.min(...w.map((p) => p.tempC));
  if (drop < MIN_DROP_C) return null;
  const t0 = w[0].at;
  const xs = w.map((p) => (p.at - t0) / 60_000);
  const ys = w.map((p) => p.tempC);
  const mx = xs.reduce((a, b) => a + b, 0) / xs.length;
  const my = ys.reduce((a, b) => a + b, 0) / ys.length;
  let num = 0;
  let den = 0;
  for (let i = 0; i < xs.length; i++) {
    num += (xs[i] - mx) * (ys[i] - my);
    den += (xs[i] - mx) ** 2;
  }
  if (den === 0) return null;
  const slope = num / den;
  return slope < 0 ? -slope : null;
}

/** Window starts: trip starts plus every door open → closed transition. */
export function pulldownStarts(doors: { at: number; open: boolean }[], tripStarts: number[]): number[] {
  const starts = [...tripStarts];
  const sorted = [...doors].sort((a, b) => a.at - b.at);
  for (let i = 1; i < sorted.length; i++) if (sorted[i - 1].open && !sorted[i].open) starts.push(sorted[i].at);
  return [...new Set(starts)].sort((a, b) => a - b);
}

export function median(xs: number[]): number | null {
  if (!xs.length) return null;
  const s = [...xs].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}

/** `(baseline − current) / baseline`; flagged only once a 4-week baseline exists. */
export function healthVerdict(current: number, baseline: number, baselineFinal: boolean) {
  const degradationPct = baseline > 0 ? (baseline - current) / baseline : 0;
  return { degradationPct, flagged: baselineFinal && degradationPct > DEGRADATION_LIMIT };
}
