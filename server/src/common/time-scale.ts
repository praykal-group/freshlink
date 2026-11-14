/**
 * Config minutes → real milliseconds. TELEMETRY_TIME_SCALE (tests only) compresses the 15-min
 * persistence window, 5-min ack escalation, etc., so pipeline tests run in seconds on the
 * production code paths (M8 tests: "time-scaled config").
 *
 * The env schema validates the variable at process start (positive, ≤ 3600, refused in
 * production); here it is only read, so unit tests without a full env do not exit.
 */
export function currentTimeScale(): number {
  const v = Number(process.env.TELEMETRY_TIME_SCALE ?? 1);
  return Number.isFinite(v) && v > 0 ? v : 1;
}

export function minutesToMs(minutes: number, scale = currentTimeScale()): number {
  return Math.max(1, Math.round((minutes * 60_000) / scale));
}
