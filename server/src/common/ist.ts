/** India Standard Time helpers (UTC+05:30, no DST). Business days in this system are IST days. */
const OFFSET_MS = 5.5 * 3_600_000;

/** `YYYY-MM-DD` + `HH:MM` in IST → UTC Date. */
export function istAt(day: string, hhmm = '00:00'): Date {
  const [h, m] = hhmm.split(':').map(Number);
  const utcMidnight = Date.parse(`${day}T00:00:00Z`);
  return new Date(utcMidnight + (h * 60 + m) * 60_000 - OFFSET_MS);
}

/** UTC Date → its IST calendar day `YYYY-MM-DD`. */
export function istDay(at: Date): string {
  return new Date(at.getTime() + OFFSET_MS).toISOString().slice(0, 10);
}

/** `YYYYMMDD` for codes. */
export const ymd = (day: string) => day.replace(/-/g, '');
