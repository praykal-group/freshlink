import { createHash, createHmac, timingSafeEqual } from 'node:crypto';

/**
 * Deterministic JSON: object keys sorted recursively, no whitespace.
 * Postgres jsonb does not keep key order, so every hash in this system is taken over this form.
 * Dates become ISO strings; undefined object members are dropped (as JSON.stringify does).
 */
export function canonicalJson(value: unknown): string {
  return JSON.stringify(normalise(value));
}

function normalise(value: unknown): unknown {
  if (value instanceof Date) return value.toISOString();
  if (Array.isArray(value)) return value.map((v) => (v === undefined ? null : normalise(v)));
  if (value && typeof value === 'object') {
    const obj = value as Record<string, unknown>;
    // Prisma.Decimal and similar expose toJSON(); honour it before descending.
    if (typeof (obj as { toJSON?: unknown }).toJSON === 'function') return normalise((obj as { toJSON(): unknown }).toJSON());
    return Object.fromEntries(
      Object.keys(obj)
        .filter((k) => obj[k] !== undefined)
        .sort()
        .map((k) => [k, normalise(obj[k])]),
    );
  }
  return value;
}

export const sha256Hex = (input: string | Buffer): string => createHash('sha256').update(input).digest('hex');

/** Record hash of a creation payload (Section 6.5). */
export const recordHash = (payload: unknown): string => sha256Hex(canonicalJson(payload));

export const GENESIS_HASH = '0'.repeat(64);

/** W-4: hash = sha256(prevHash || eventType || canonicalJson(payload) || occurredAt.toISOString()). */
export function traceHash(prevHash: string, eventType: string, payload: unknown, occurredAt: Date): string {
  return sha256Hex(prevHash + eventType + canonicalJson(payload) + occurredAt.toISOString());
}

export interface ChainLink {
  seq: number;
  eventType: string;
  payload: unknown;
  occurredAt: Date;
  prevHash: string;
  hash: string;
}

export interface ChainVerdict {
  valid: boolean;
  count: number;
  /** First seq where the chain breaks. */
  brokenAtSeq?: number;
  reason?: 'SEQ_GAP' | 'PREV_HASH_MISMATCH' | 'HASH_MISMATCH';
}

/** Recomputes the whole chain (events must be sorted by seq). */
export function verifyChain(events: ChainLink[]): ChainVerdict {
  let prev = GENESIS_HASH;
  for (let i = 0; i < events.length; i++) {
    const e = events[i];
    if (e.seq !== i + 1) return { valid: false, count: events.length, brokenAtSeq: e.seq, reason: 'SEQ_GAP' };
    if (e.prevHash !== prev) return { valid: false, count: events.length, brokenAtSeq: e.seq, reason: 'PREV_HASH_MISMATCH' };
    if (traceHash(e.prevHash, e.eventType, e.payload, e.occurredAt) !== e.hash) {
      return { valid: false, count: events.length, brokenAtSeq: e.seq, reason: 'HASH_MISMATCH' };
    }
    prev = e.hash;
  }
  return { valid: true, count: events.length };
}

/** Trace URL signature: base64url(HMAC-SHA256(code, key))[:22] (Section 6.5). */
export function traceSignature(code: string, key: string): string {
  return createHmac('sha256', key).update(code).digest('base64url').slice(0, 22);
}

export function verifyTraceSignature(code: string, sig: unknown, key: string): boolean {
  if (typeof sig !== 'string' || sig.length !== 22) return false;
  const expected = Buffer.from(traceSignature(code, key));
  const given = Buffer.from(sig);
  return given.length === expected.length && timingSafeEqual(given, expected);
}
