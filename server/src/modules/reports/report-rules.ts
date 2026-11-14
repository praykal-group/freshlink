/** Pure helpers for the compliance / traceability reports (SYN-15). */

export interface TempRow {
  at: string; // ISO minute
  tempC: number;
}

export interface Excursion {
  from: string;
  to: string;
  minutes: number;
  peakC: number;
  direction: 'ABOVE' | 'BELOW';
}

export function tempStats(rows: TempRow[]) {
  if (!rows.length) return { count: 0, minC: null, maxC: null, meanC: null };
  const t = rows.map((r) => r.tempC);
  return {
    count: rows.length,
    minC: Math.min(...t),
    maxC: Math.max(...t),
    meanC: Math.round((t.reduce((a, b) => a + b, 0) / t.length) * 100) / 100,
  };
}

/** Contiguous runs of 1-min readings outside [min, max]; a gap > `maxGapMin` ends a run. */
export function excursions(rows: TempRow[], min: number, max: number, maxGapMin = 5): Excursion[] {
  const out: Excursion[] = [];
  let cur: (Excursion & { lastAt: number }) | null = null;
  for (const r of [...rows].sort((a, b) => a.at.localeCompare(b.at))) {
    const at = Date.parse(r.at);
    const dir = r.tempC > max ? 'ABOVE' : r.tempC < min ? 'BELOW' : null;
    if (cur && (!dir || dir !== cur.direction || at - cur.lastAt > maxGapMin * 60_000)) {
      out.push(close(cur));
      cur = null;
    }
    if (!dir) continue;
    if (!cur) cur = { from: r.at, to: r.at, minutes: 0, peakC: r.tempC, direction: dir, lastAt: at };
    else {
      cur.to = r.at;
      cur.lastAt = at;
      cur.peakC = dir === 'ABOVE' ? Math.max(cur.peakC, r.tempC) : Math.min(cur.peakC, r.tempC);
    }
  }
  if (cur) out.push(close(cur));
  return out;
}

function close(e: Excursion & { lastAt: number }): Excursion {
  const { lastAt, ...rest } = e;
  void lastAt;
  return { ...rest, minutes: Math.round((Date.parse(e.to) - Date.parse(e.from)) / 60_000) + 1 };
}

/**
 * FSMA 204-style Critical Tracking Event for a trace event type (our own mapping, D-106).
 * Events that are not CTEs (grading, tagging, shelf-life updates…) return null and are left out.
 */
export function cteOf(eventType: string, category: string): string | null {
  switch (eventType) {
    case 'REGISTERED':
      return category === 'FISH' ? 'FIRST_LAND_BASED_RECEIVING' : 'HARVESTING';
    case 'STORED':
      return 'COOLING';
    case 'DEPARTED':
    case 'DIVERTED':
      return 'SHIPPING';
    case 'RESCUED':
      return 'SHIPPING';
    case 'RECEIVED':
    case 'DELIVERED':
      return 'RECEIVING';
    default:
      return null;
  }
}

/** Report date range: ISO instants, from < to, at most `maxDays`. */
export function parseRange(from: string | undefined, to: string | undefined, maxDays: number): { from: Date; to: Date } | string {
  if (!from || !to) return 'from and to are required (ISO 8601)';
  const f = new Date(from);
  const t = new Date(to);
  if (Number.isNaN(f.getTime()) || Number.isNaN(t.getTime())) return 'from and to must be ISO 8601 instants';
  if (f >= t) return 'from must be before to';
  if (t.getTime() - f.getTime() > maxDays * 86_400_000) return `range is limited to ${maxDays} days`;
  return { from: f, to: t };
}
