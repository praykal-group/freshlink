import type { ProductCategory } from '@prisma/client';

/** Batch dates use India time: the operator's calendar day decides the code. */
const IST = 'Asia/Kolkata';

export function istYmd(at: Date): string {
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone: IST, year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(at);
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? '';
  return `${get('year')}${get('month')}${get('day')}`;
}

/** `{FSH|PRD}-{yyyymmdd}-{site code}-` (Section 6.5); the 4-digit sequence is appended under a lock. */
export function batchCodePrefix(category: ProductCategory, siteCode: string, at: Date): string {
  return `${category === 'FISH' ? 'FSH' : 'PRD'}-${istYmd(at)}-${siteCode}-`;
}

export function batchCode(prefix: string, seq: number): string {
  if (seq < 1 || seq > 9999) throw new RangeError('batch sequence out of range (1..9999 per site per day)');
  return `${prefix}${String(seq).padStart(4, '0')}`;
}

/** FO-FR-13: direct edits only within `windowMin` of creation, by an operator of the same site. */
export function withinEditWindow(createdAt: Date, now: Date, windowMin: number): boolean {
  const ageMs = now.getTime() - createdAt.getTime();
  return ageMs >= 0 && ageMs <= windowMin * 60_000;
}

export interface BatchFields {
  vesselId?: string;
  farmRef?: string;
  iceToFishRatio?: number;
  initialCoreTemp?: number;
  maturityIndex?: number;
  brix?: number;
  fieldTemp?: number;
  fieldHumidity?: number;
}

export interface FieldProblem {
  field: string;
  message: string;
}

/**
 * Category-specific checks (FO-FR-02/03, FO-NFR range validation). Generic ranges live on the DTO;
 * these are the rules that depend on whether the product is fish or produce.
 */
export function categoryProblems(category: ProductCategory, f: BatchFields, partial = false): FieldProblem[] {
  const out: FieldProblem[] = [];
  const need = (field: keyof BatchFields) => {
    if (!partial && (f[field] === undefined || f[field] === null || f[field] === '')) out.push({ field, message: 'required' });
  };
  const forbid = (fields: (keyof BatchFields)[], kind: string) => {
    for (const field of fields) if (f[field] !== undefined && f[field] !== null) out.push({ field, message: `not used for ${kind} batches` });
  };
  if (category === 'FISH') {
    need('vesselId');
    need('iceToFishRatio');
    need('initialCoreTemp');
    if (f.initialCoreTemp !== undefined && (f.initialCoreTemp < -2 || f.initialCoreTemp > 10)) {
      out.push({ field: 'initialCoreTemp', message: 'fish core temperature must be between -2 and +10 °C' });
    }
    forbid(['farmRef', 'maturityIndex', 'brix', 'fieldTemp', 'fieldHumidity'], 'fish');
  } else {
    need('farmRef');
    need('maturityIndex');
    forbid(['vesselId', 'iceToFishRatio', 'initialCoreTemp'], 'produce');
  }
  return out;
}
