/** Human labels for trace events on the public page. */
export const EVENT_LABELS: Record<string, string> = {
  REGISTERED: 'Registered',
  TAGGED: 'Tagged',
  IMAGED: 'Photographed for grading',
  GRADED: 'Quality graded',
  GRADE_DISPUTED: 'Grade disputed',
  GRADE_RESOLVED: 'Grade confirmed',
  STORED: 'Placed in cold storage',
  BATCH_CORRECTED: 'Record corrected',
  ALLOCATED: 'Allocated to an order',
  LOADED: 'Loaded on truck',
  DEPARTED: 'Departed',
  EXCURSION: 'Temperature excursion',
  SHELF_LIFE_UPDATED: 'Shelf life re-estimated',
  DIVERTED: 'Diverted',
  RESCUED: 'Transferred to rescue truck',
  RECEIVED: 'Received',
  DELIVERED: 'Delivered',
  REJECTED: 'Rejected',
};

const fmt = new Intl.DateTimeFormat('en-IN', { timeZone: 'Asia/Kolkata', dateStyle: 'medium', timeStyle: 'short' });
export const istTime = (d: Date) => fmt.format(d);

/**
 * One short, non-personal detail per event. Never shows user ids, file keys or tag UIDs.
 */
export function eventDetail(type: string, payload: unknown): string | undefined {
  const p = (payload ?? {}) as Record<string, unknown>;
  switch (type) {
    case 'REGISTERED':
      return typeof p.siteCode === 'string' ? p.siteCode : undefined;
    case 'TAGGED':
      return typeof p.tagType === 'string' ? p.tagType.replace('_', ' ') : undefined;
    case 'IMAGED':
      return typeof p.view === 'string' ? p.view.toLowerCase() : undefined;
    case 'GRADED':
    case 'GRADE_RESOLVED':
      return typeof p.grade === 'string' ? `Grade ${p.grade}` : undefined;
    case 'STORED':
      return typeof p.unitType === 'string' ? p.unitType.replace('_', ' ').toLowerCase() : undefined;
    case 'BATCH_CORRECTED':
      return p.changes && typeof p.changes === 'object' ? Object.keys(p.changes).join(', ') : undefined;
    case 'RECEIVED':
    case 'REJECTED':
      return [p.siteCode, p.outcome].filter((x) => typeof x === 'string').join(' · ') || undefined;
    default:
      return undefined;
  }
}
