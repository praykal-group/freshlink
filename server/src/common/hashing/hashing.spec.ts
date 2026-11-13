import {
  canonicalJson,
  type ChainLink,
  GENESIS_HASH,
  recordHash,
  traceHash,
  traceSignature,
  verifyChain,
  verifyTraceSignature,
} from './hashing';

// M4: hash chain (W-4, SYN-14) and signed trace URL (SYN-09).

function buildChain(payloads: Array<[string, Record<string, unknown>]>): ChainLink[] {
  let prev = GENESIS_HASH;
  return payloads.map(([eventType, payload], i) => {
    const occurredAt = new Date(Date.UTC(2026, 10, 13, 10, i));
    const hash = traceHash(prev, eventType, payload, occurredAt);
    const link = { seq: i + 1, eventType, payload, occurredAt, prevHash: prev, hash };
    prev = hash;
    return link;
  });
}

/** What jsonb does: same content, keys in another order. */
function reorderKeys(v: unknown): unknown {
  if (Array.isArray(v)) return v.map(reorderKeys);
  if (v && typeof v === 'object') {
    return Object.fromEntries(Object.entries(v as Record<string, unknown>).reverse().map(([k, x]) => [k, reorderKeys(x)]));
  }
  return v;
}

describe('canonicalJson', () => {
  it('sorts keys recursively and is order independent', () => {
    expect(canonicalJson({ b: 1, a: { d: [3, { z: 1, y: 2 }], c: 2 } })).toBe('{"a":{"c":2,"d":[3,{"y":2,"z":1}]},"b":1}');
    expect(canonicalJson({ x: 1, y: 2 })).toBe(canonicalJson({ y: 2, x: 1 }));
  });

  it('drops undefined members and serialises dates as ISO', () => {
    expect(canonicalJson({ a: undefined, d: new Date('2026-11-13T00:00:00Z') })).toBe('{"d":"2026-11-13T00:00:00.000Z"}');
  });

  it('gives a stable record hash for the same payload in any key order', () => {
    expect(recordHash({ weightKg: 120, productId: 'p' })).toBe(recordHash({ productId: 'p', weightKg: 120 }));
    expect(recordHash({ weightKg: 120 })).not.toBe(recordHash({ weightKg: 121 }));
  });
});

describe('trace hash chain', () => {
  const chain = buildChain([
    ['REGISTERED', { code: 'FSH-20261113-DCK-PTN-0001', weightKg: 120, siteCode: 'DCK-PTN' }],
    ['TAGGED', { tagType: 'NFC', tagUid: '04:A1:B2:C3' }],
    ['STORED', { unitCode: 'BC-1', unitType: 'BLAST_CHILLER' }],
  ]);

  it('first event links to 64 zeros', () => {
    expect(chain[0].prevHash).toBe('0'.repeat(64));
    expect(chain[0].hash).toMatch(/^[0-9a-f]{64}$/);
  });

  it('verifies an intact chain', () => {
    expect(verifyChain(chain)).toEqual({ valid: true, count: 3 });
  });

  it('still verifies after the database reorders jsonb keys', () => {
    const fromDb = chain.map((l) => ({ ...l, payload: reorderKeys(l.payload) }));
    expect(verifyChain(fromDb).valid).toBe(true);
  });

  it('detects a tampered payload (e.g. weight changed directly in the table)', () => {
    const tampered = chain.map((l) => ({ ...l }));
    tampered[0] = { ...tampered[0], payload: { ...(tampered[0].payload as object), weightKg: 150 } };
    expect(verifyChain(tampered)).toMatchObject({ valid: false, brokenAtSeq: 1, reason: 'HASH_MISMATCH' });
  });

  it('detects a re-hashed row whose successor still points at the old hash', () => {
    const t = chain.map((l) => ({ ...l }));
    const p = { ...(t[1].payload as object), tagUid: 'FAKE' };
    t[1] = { ...t[1], payload: p, hash: traceHash(t[1].prevHash, t[1].eventType, p, t[1].occurredAt) };
    expect(verifyChain(t)).toMatchObject({ valid: false, brokenAtSeq: 3, reason: 'PREV_HASH_MISMATCH' });
  });

  it('detects a deleted event', () => {
    expect(verifyChain([chain[0], chain[2]])).toMatchObject({ valid: false, reason: 'SEQ_GAP' });
  });

  it('detects a changed timestamp', () => {
    const t = chain.map((l) => ({ ...l }));
    t[2] = { ...t[2], occurredAt: new Date(t[2].occurredAt.getTime() + 1000) };
    expect(verifyChain(t)).toMatchObject({ valid: false, brokenAtSeq: 3 });
  });

  it('an empty chain is trivially valid', () => {
    expect(verifyChain([])).toEqual({ valid: true, count: 0 });
  });
});

describe('trace URL signature', () => {
  const key = 'k'.repeat(40);
  const code = 'PRD-20261113-FRM-GNG-0007';

  it('is 22 url-safe characters', () => {
    expect(traceSignature(code, key)).toMatch(/^[A-Za-z0-9_-]{22}$/);
  });

  it('accepts the right signature and rejects everything else', () => {
    const s = traceSignature(code, key);
    expect(verifyTraceSignature(code, s, key)).toBe(true);
    expect(verifyTraceSignature('PRD-20261113-FRM-GNG-0008', s, key)).toBe(false); // other batch
    expect(verifyTraceSignature(code, s, 'x'.repeat(40))).toBe(false); // other key
    expect(verifyTraceSignature(code, s.slice(0, 21), key)).toBe(false); // truncated
    expect(verifyTraceSignature(code, undefined, key)).toBe(false);
    expect(verifyTraceSignature(code, ['a'], key)).toBe(false);
  });
});
