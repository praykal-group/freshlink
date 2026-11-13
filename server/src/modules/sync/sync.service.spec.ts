import type { AuthUser } from '../../common/auth/auth-user';
import { AppError } from '../../common/errors/app-error';
import { orderOps, SyncService } from './sync.service';

// M4: duplicate sync op → same result and no second write; ordering; role check; error storage.
const operator = { id: 'op-1', role: 'OPERATOR', siteId: 's1' } as AuthUser;
const driver = { id: 'dr-1', role: 'DRIVER' } as AuthUser;
const BATCH_ID = '0f8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a7b';

function fakePrisma() {
  const rows = new Map<string, { clientOpId: string; userId: string; type: string; result: unknown }>();
  return {
    rows,
    syncOp: {
      findUnique: jest.fn(async ({ where }: { where: { clientOpId: string } }) => rows.get(where.clientOpId) ?? null),
      create: jest.fn(async ({ data }: { data: { clientOpId: string; userId: string; type: string; result: unknown } }) => {
        rows.set(data.clientOpId, data);
        return data;
      }),
    },
  };
}

const tagPayload = { batchId: BATCH_ID, tagType: 'NFC', tagUid: '04A1B2C3' };
const op = (id: string, type: string, payload: Record<string, unknown>, capturedAt = '2026-11-13T10:00:00Z') => ({
  clientOpId: id,
  type: type as never,
  payload,
  capturedAt,
});

describe('orderOps', () => {
  it('sorts by capturedAt and keeps client order for equal times', () => {
    const ops = [
      { id: 'c', capturedAt: '2026-11-13T10:02:00Z' },
      { id: 'a', capturedAt: '2026-11-13T10:00:00Z' },
      { id: 'b1', capturedAt: '2026-11-13T10:01:00Z' },
      { id: 'b2', capturedAt: '2026-11-13T10:01:00Z' },
    ];
    expect(orderOps(ops).map((o) => o.id)).toEqual(['a', 'b1', 'b2', 'c']);
  });
});

describe('SyncService', () => {
  let prisma: ReturnType<typeof fakePrisma>;
  let batches: { attachTag: jest.Mock; create: jest.Mock };
  let sync: SyncService;

  beforeEach(() => {
    prisma = fakePrisma();
    batches = { attachTag: jest.fn().mockResolvedValue({ id: 'tag-1' }), create: jest.fn() };
    sync = new SyncService(prisma as never, batches as never);
  });

  it('applies an op once; the duplicate replays the stored result without a second write', async () => {
    const o = op('11111111-1111-4111-8111-111111111111', 'TAG_ATTACH', tagPayload);
    const first = await sync.process(operator, [o]);
    const second = await sync.process(operator, [o]);

    expect(first.results[0]).toMatchObject({ status: 'APPLIED', data: { id: 'tag-1' } });
    expect(second.results[0]).toMatchObject({ status: 'APPLIED', data: { id: 'tag-1' }, replayed: true });
    expect(batches.attachTag).toHaveBeenCalledTimes(1);
    expect(prisma.syncOp.create).toHaveBeenCalledTimes(1);
  });

  it('stores 4xx rejections so retries get the same answer', async () => {
    batches.attachTag.mockRejectedValueOnce(new AppError('TAG_IN_USE', 'in use', 409));
    const o = op('22222222-2222-4222-8222-222222222222', 'TAG_ATTACH', tagPayload);
    expect((await sync.process(operator, [o])).results[0]).toMatchObject({ status: 'REJECTED', error: { code: 'TAG_IN_USE' } });
    expect((await sync.process(operator, [o])).results[0]).toMatchObject({ status: 'REJECTED', replayed: true });
    expect(batches.attachTag).toHaveBeenCalledTimes(1);
  });

  it('does NOT store 5xx errors, so the phone retries', async () => {
    batches.attachTag.mockRejectedValueOnce(new Error('db down')).mockResolvedValueOnce({ id: 'tag-2' });
    const o = op('33333333-3333-4333-8333-333333333333', 'TAG_ATTACH', tagPayload);
    expect((await sync.process(operator, [o])).results[0].status).toBe('ERROR');
    expect((await sync.process(operator, [o])).results[0]).toMatchObject({ status: 'APPLIED', data: { id: 'tag-2' } });
  });

  it('validates the payload (bad batchId / unknown fields → REJECTED)', async () => {
    const bad = await sync.process(operator, [
      op('44444444-4444-4444-8444-444444444444', 'TAG_ATTACH', { batchId: 'x', tagType: 'NFC', tagUid: '04A1B2C3' }),
      op('55555555-5555-4555-8555-555555555555', 'TAG_ATTACH', { ...tagPayload, hack: true }),
    ]);
    expect(bad.results.map((r) => r.status)).toEqual(['REJECTED', 'REJECTED']);
    expect(batches.attachTag).not.toHaveBeenCalled();
  });

  it('applies the same role rules as REST (driver cannot create batches through sync)', async () => {
    const r = await sync.process(driver, [op('66666666-6666-4666-8666-666666666666', 'BATCH_CREATE', {})]);
    expect(r.results[0]).toMatchObject({ status: 'REJECTED', error: { code: 'FORBIDDEN_ROLE' } });
    expect(batches.create).not.toHaveBeenCalled();
  });

  it('answers UNSUPPORTED for later-milestone types without storing them', async () => {
    const r = await sync.process(driver, [op('77777777-7777-4777-8777-777777777777', 'GPS_POINTS', { points: [] })]);
    expect(r.results[0].status).toBe('UNSUPPORTED');
    expect(prisma.syncOp.create).not.toHaveBeenCalled();
  });

  it('refuses a clientOpId that belongs to another user', async () => {
    const o = op('88888888-8888-4888-8888-888888888888', 'TAG_ATTACH', tagPayload);
    await sync.process(operator, [o]);
    const r = await sync.process({ ...operator, id: 'op-2' }, [o]);
    expect(r.results[0]).toMatchObject({ status: 'REJECTED', error: { code: 'DUPLICATE' } });
  });
});
