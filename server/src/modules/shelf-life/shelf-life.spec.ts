import { MlCallError, MlClient } from '../../infra/ml/ml-client.service';
import { isSignificantChange, q10RemainingH, refTempOf } from './q10';
import { ShelfLifeService } from './shelf-life.service';

describe('backend Q10 (same numbers as ml/service tests)', () => {
  it('at the reference temperature: base − elapsed', () => {
    expect(q10RemainingH({ baseShelfLifeH: 192, q10: 2.5, refTempC: 2, meanTempC: 2, hoursSinceHarvest: 24 })).toBe(168);
  });

  it('10 °C warmer divides the total by Q10', () => {
    expect(q10RemainingH({ baseShelfLifeH: 192, q10: 2.5, refTempC: 2, meanTempC: 12, hoursSinceHarvest: 24 })).toBeCloseTo(192 / 2.5 - 24, 2);
  });

  it('never goes negative', () => {
    expect(q10RemainingH({ baseShelfLifeH: 96, q10: 3, refTempC: 1, meanTempC: 30, hoursSinceHarvest: 500 })).toBe(0);
  });

  it('reference temperature is the middle of the safe range', () => {
    expect(refTempOf(13, 15)).toBe(14);
  });

  it('trace only on first estimate or a change of ≥ 2 h', () => {
    expect(isSignificantChange(null, 100)).toBe(true);
    expect(isSignificantChange(100, 101.9)).toBe(false);
    expect(isSignificantChange(100, 98)).toBe(true);
  });
});

function setup(opts: { ml?: jest.Mock; batch?: Record<string, unknown> | null } = {}) {
  const batch =
    opts.batch === undefined
      ? {
          id: 'b1',
          status: 'GRADED',
          currentGrade: 'A',
          caughtOrHarvestedAt: new Date(Date.now() - 24 * 3_600_000),
          remainingShelfLifeH: null,
          product: { code: 'ROHU', category: 'FISH', safeTempMin: 0, safeTempMax: 4, baseShelfLifeH: 192, q10: 2.5 },
          exposure: null,
        }
      : opts.batch;
  const tx = {
    shelfLifeEstimate: { create: jest.fn(async ({ data }) => ({ id: 'e1', ...data })) },
    batch: { update: jest.fn() },
  };
  const prisma = {
    batch: { findUnique: jest.fn().mockResolvedValue(batch) },
    $transaction: jest.fn(async (fn: (t: typeof tx) => unknown) => fn(tx)),
  };
  const ml = { post: opts.ml ?? jest.fn() };
  const trace = { append: jest.fn() };
  const cargo = { batchUpdated: jest.fn() };
  return { service: new ShelfLifeService(prisma as never, ml as never, trace as never, cargo as never), tx, ml, trace, cargo };
}

describe('ShelfLifeService.recompute', () => {
  it('sends product reference values and the exposure, stores the ML answer and traces the first estimate', async () => {
    const s = setup({
      ml: jest.fn().mockResolvedValue({ results: [{ batchId: 'b1', remainingH: 168, survivalCurve: [{ h: 0, p: 1 }], method: 'Q10_FALLBACK', modelVersion: 'q10-1' }] }),
    });
    const r = await s.service.recompute('b1', 'GRADE', 'op-1');

    const [, body] = s.ml.post.mock.calls[0];
    expect(body.items[0]).toMatchObject({ productCode: 'ROHU', grade: 'A', baseShelfLifeH: 192, q10: 2.5, refTempC: 2, meanTempC: 2 });
    expect(body.items[0].hoursSinceHarvest).toBeCloseTo(24, 1);
    expect(s.tx.batch.update).toHaveBeenCalledWith({ where: { id: 'b1' }, data: { remainingShelfLifeH: 168, shelfLifeUpdatedAt: expect.any(Date) } });
    expect(s.trace.append).toHaveBeenCalledWith(s.tx, 'b1', 'SHELF_LIFE_UPDATED', expect.objectContaining({ remainingH: 168, previousH: null }), 'op-1', expect.any(Date));
    expect(s.cargo.batchUpdated).toHaveBeenCalledWith(expect.objectContaining({ batchId: 'b1', remainingShelfLifeH: 168 }));
    expect(r).toMatchObject({ remainingH: 168, trigger: 'GRADE' });
  });

  it('ML down → backend Q10 still stores a value (ML-02)', async () => {
    const s = setup({ ml: jest.fn().mockRejectedValue(new MlCallError(0, 'ML_UNREACHABLE', 'refused')) });
    const r = await s.service.recompute('b1', 'SCHEDULED');
    expect(r).toMatchObject({ method: 'Q10_FALLBACK', modelVersion: 'backend-q10-1' });
    expect(r?.remainingH).toBeCloseTo(168, 0);
  });

  it('does not trace a change under 2 h', async () => {
    const s = setup({
      batch: {
        id: 'b1', status: 'STORED', currentGrade: null, caughtOrHarvestedAt: new Date(), remainingShelfLifeH: 100,
        product: { code: 'ROHU', category: 'FISH', safeTempMin: 0, safeTempMax: 4, baseShelfLifeH: 192, q10: 2.5 }, exposure: null,
      },
      ml: jest.fn().mockResolvedValue({ results: [{ batchId: 'b1', remainingH: 99, survivalCurve: [], method: 'COX', modelVersion: 'cox:v1' }] }),
    });
    await s.service.recompute('b1', 'SCHEDULED');
    expect(s.trace.append).not.toHaveBeenCalled();
    expect(s.tx.batch.update).toHaveBeenCalled();
  });

  it('skips finished batches', async () => {
    const s = setup({ batch: { id: 'b1', status: 'DELIVERED' } });
    expect(await s.service.recompute('b1', 'SCHEDULED')).toBeNull();
    expect(s.ml.post).not.toHaveBeenCalled();
  });
});

describe('MlClient', () => {
  const config = { get: (k: string) => (k === 'ML_SERVICE_URL' ? 'http://ml:8000/' : 'tok-12345678') };
  const realFetch = global.fetch;
  afterEach(() => {
    global.fetch = realFetch;
  });

  it('sends the internal token and maps the ML error envelope', async () => {
    global.fetch = jest.fn().mockResolvedValue(
      new Response(JSON.stringify({ error: { code: 'MODEL_NOT_AVAILABLE', message: 'none', details: { reason: 'r' } } }), { status: 503 }),
    ) as never;
    const err = await new MlClient(config as never).post('/v1/x', {}, 1000).catch((e) => e);
    expect(err).toMatchObject({ status: 503, code: 'MODEL_NOT_AVAILABLE', details: { reason: 'r' } });
    const [url, init] = (global.fetch as jest.Mock).mock.calls[0];
    expect(url).toBe('http://ml:8000/v1/x');
    expect(init.headers['x-internal-token']).toBe('tok-12345678');
  });

  it('network failure → status 0', async () => {
    global.fetch = jest.fn().mockRejectedValue(new TypeError('fetch failed')) as never;
    expect(await new MlClient(config as never).post('/v1/x', {}, 1000).catch((e) => e)).toMatchObject({ status: 0, code: 'ML_UNREACHABLE' });
  });
});
