import type { AuthUser } from '../../common/auth/auth-user';
import { AppError } from '../../common/errors/app-error';
import { MlCallError } from '../../infra/ml/ml-client.service';
import { pickGradingImages } from './grading-rules';
import { GradingService } from './grading.service';

const op = { id: 'op-1', role: 'OPERATOR', siteId: 's1' } as AuthUser;
const mgr = { id: 'm-1', role: 'MANAGER', siteId: null } as AuthUser;
const BATCH = '0f8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a7b';
const at = (m: number) => new Date(Date.UTC(2026, 10, 13, 10, m));

describe('pickGradingImages', () => {
  it('needs TOP, SIDE and CLOSEUP and lists what is missing', () => {
    expect(pickGradingImages([{ view: 'TOP', s3Key: 't', capturedAt: at(0) }])).toEqual({ ok: false, missing: ['SIDE', 'CLOSEUP'] });
  });

  it('uses the latest photo per view, in TOP, SIDE, CLOSEUP order; other views are ignored', () => {
    const r = pickGradingImages([
      { view: 'CLOSEUP', s3Key: 'c1', capturedAt: at(1) },
      { view: 'TOP', s3Key: 't-old', capturedAt: at(0) },
      { view: 'SIDE', s3Key: 's1', capturedAt: at(1) },
      { view: 'TOP', s3Key: 't-new', capturedAt: at(5) },
      { view: 'DAMAGE', s3Key: 'd', capturedAt: at(9) },
    ]);
    expect(r).toEqual({ ok: true, keys: ['t-new', 's1', 'c1'] });
  });
});

function setup(opts: { images?: { view: string; s3Key: string; capturedAt: Date }[]; ml?: jest.Mock } = {}) {
  const images = opts.images ?? [
    { view: 'TOP', s3Key: 'k1', capturedAt: at(0) },
    { view: 'SIDE', s3Key: 'k2', capturedAt: at(0) },
    { view: 'CLOSEUP', s3Key: 'k3', capturedAt: at(0) },
  ];
  const tx = {
    qualityGrade: {
      create: jest.fn(async ({ data }) => ({ id: 'g1', createdAt: new Date(), ...data })),
      updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      findUniqueOrThrow: jest.fn().mockResolvedValue({ id: 'g1', confidence: 0.8 }),
    },
    batch: { update: jest.fn() },
  };
  const prisma = {
    product: { findUniqueOrThrow: jest.fn().mockResolvedValue({ category: 'PRODUCE' }) },
    batchImage: { findMany: jest.fn().mockResolvedValue(images) },
    qualityGrade: { findFirst: jest.fn(), findUnique: jest.fn() },
    $transaction: jest.fn(async (fn: (t: typeof tx) => unknown) => fn(tx)),
  };
  const batches = {
    loadForUser: jest.fn().mockResolvedValue({ id: BATCH, status: 'REGISTERED', currentSiteId: 's1', productId: 'p' }),
    storagePath: jest.fn().mockResolvedValue({ path: 'RIPENING_CHAMBER' }),
  };
  const files = { internalUrl: jest.fn(async (k: string) => `https://s3/${k}`) };
  const ml = {
    post:
      opts.ml ??
      jest.fn().mockResolvedValue({ batchId: BATCH, grade: 'B', confidence: 0.81, defects: [{ class: 'bruise', conf: 0.81, box: [], areaPct: 4 }], perImage: [], modelVersion: 'vision_produce:v1', latencyMs: 640 }),
  };
  const trace = { append: jest.fn() };
  const shelfLife = { recompute: jest.fn().mockResolvedValue({}) };
  const events = { publish: jest.fn() };
  const service = new GradingService(prisma as never, batches as never, files as never, ml as never, trace as never, shelfLife as never, events as never);
  return { service, prisma, tx, ml, trace, shelfLife, files };
}

async function code(p: Promise<unknown>) {
  try {
    await p;
    return 'OK';
  } catch (e) {
    return e instanceof AppError ? `${e.getStatus()} ${e.code}` : String(e);
  }
}

describe('GradingService.grade', () => {
  it('sends the 3 presigned photos, stores an AUTO grade, updates the batch, traces GRADED and recomputes shelf life', async () => {
    const s = setup();
    const r = (await s.service.grade(op, BATCH)) as { grade: string; storagePath: unknown; mlLatencyMs: number };

    expect(s.ml.post).toHaveBeenCalledWith(
      '/v1/vision/grade',
      { batchId: BATCH, category: 'PRODUCE', imageUrls: ['https://s3/k1', 'https://s3/k2', 'https://s3/k3'] },
      expect.any(Number),
    );
    expect(s.tx.qualityGrade.create).toHaveBeenCalledWith({ data: expect.objectContaining({ grade: 'B', source: 'AUTO', modelVersion: 'vision_produce:v1' }) });
    expect(s.tx.batch.update).toHaveBeenCalledWith({ where: { id: BATCH }, data: { currentGrade: 'B', status: 'GRADED' } });
    expect(s.trace.append).toHaveBeenCalledWith(s.tx, BATCH, 'GRADED', expect.objectContaining({ grade: 'B', defectClasses: ['bruise'] }), 'op-1');
    expect(s.shelfLife.recompute).toHaveBeenCalledWith(BATCH, 'GRADE', 'op-1');
    expect(r).toMatchObject({ grade: 'B', mlLatencyMs: 640, storagePath: { path: 'RIPENING_CHAMBER' } });
  });

  it('missing photos → 409 IMAGES_REQUIRED without calling ML', async () => {
    const s = setup({ images: [{ view: 'TOP', s3Key: 'k1', capturedAt: at(0) }] });
    expect(await code(s.service.grade(op, BATCH))).toBe('409 IMAGES_REQUIRED');
    expect(s.ml.post).not.toHaveBeenCalled();
  });

  it('no model loaded / ML down → 503 GRADING_UNAVAILABLE and nothing stored (app retries later)', async () => {
    for (const err of [new MlCallError(503, 'MODEL_NOT_AVAILABLE', 'x'), new MlCallError(0, 'ML_UNREACHABLE', 'x')]) {
      const s = setup({ ml: jest.fn().mockRejectedValue(err) });
      expect(await code(s.service.grade(op, BATCH))).toBe('503 GRADING_UNAVAILABLE');
      expect(s.prisma.$transaction).not.toHaveBeenCalled();
    }
  });

  it('unreadable photo → 422 GRADING_FAILED', async () => {
    const s = setup({ ml: jest.fn().mockRejectedValue(new MlCallError(422, 'IMAGE_INVALID', 'image 1 is not a readable image')) });
    expect(await code(s.service.grade(op, BATCH))).toBe('422 GRADING_FAILED');
  });

  it('a shelf-life failure does not undo the grade', async () => {
    const s = setup();
    s.shelfLife.recompute.mockRejectedValueOnce(new Error('db hiccup'));
    expect(await code(s.service.grade(op, BATCH))).toBe('OK');
    expect(s.tx.qualityGrade.create).toHaveBeenCalled();
  });
});

describe('GradingService dispute / resolve', () => {
  it('disputes the latest grade once', async () => {
    const s = setup();
    s.prisma.qualityGrade.findFirst.mockResolvedValue({ id: 'g1', grade: 'C', disputed: false });
    expect(await code(s.service.dispute(op, BATCH, 'looks fine to me'))).toBe('OK');
    expect(s.trace.append).toHaveBeenCalledWith(s.tx, BATCH, 'GRADE_DISPUTED', { gradeId: 'g1', grade: 'C', reason: 'looks fine to me' }, 'op-1');

    s.prisma.qualityGrade.findFirst.mockResolvedValue({ id: 'g1', grade: 'C', disputed: true });
    expect(await code(s.service.dispute(op, BATCH, 'again'))).toBe('409 ALREADY_DISPUTED');
  });

  it('cannot dispute an ungraded batch', async () => {
    const s = setup();
    s.prisma.qualityGrade.findFirst.mockResolvedValue(null);
    expect(await code(s.service.dispute(op, BATCH, 'why'))).toBe('409 NO_GRADE');
  });

  it('resolve writes a MANUAL grade, keeps the AUTO row, updates the batch and recomputes shelf life', async () => {
    const s = setup();
    s.prisma.qualityGrade.findUnique.mockResolvedValue({ id: 'g1', batchId: BATCH, grade: 'C', disputed: true });
    expect(await code(s.service.resolve(mgr, 'g1', 'B'))).toBe('OK');
    expect(s.tx.qualityGrade.create).toHaveBeenCalledWith({ data: expect.objectContaining({ grade: 'B', source: 'MANUAL', resolvedBy: 'm-1' }) });
    expect(s.tx.batch.update).toHaveBeenCalledWith({ where: { id: BATCH }, data: { currentGrade: 'B' } });
    expect(s.trace.append).toHaveBeenCalledWith(s.tx, BATCH, 'GRADE_RESOLVED', expect.objectContaining({ previous: 'C', grade: 'B' }), 'm-1');
    expect(s.shelfLife.recompute).toHaveBeenCalledWith(BATCH, 'MANUAL', 'm-1');
  });

  it('resolve refuses non-disputed and already-resolved grades', async () => {
    const s = setup();
    s.prisma.qualityGrade.findUnique.mockResolvedValue({ id: 'g1', batchId: BATCH, grade: 'C', disputed: false });
    expect(await code(s.service.resolve(mgr, 'g1', 'B'))).toBe('409 NOT_DISPUTED');
    s.prisma.qualityGrade.findUnique.mockResolvedValue({ id: 'g1', batchId: BATCH, grade: 'C', disputed: true });
    s.tx.qualityGrade.updateMany.mockResolvedValueOnce({ count: 0 });
    expect(await code(s.service.resolve(mgr, 'g1', 'B'))).toBe('409 ALREADY_RESOLVED');
  });
});
