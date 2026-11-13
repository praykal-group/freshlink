import type { AuthUser } from '../../common/auth/auth-user';
import { AppError } from '../../common/errors/app-error';
import { BatchesService } from './batches.service';

// M4: operator from another site → 403; edit window over the service; idempotent create replay.
const BATCH_ID = '0f8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a7b';
const opA = { id: 'op-a', role: 'OPERATOR', siteId: 'site-a' } as AuthUser;
const opB = { id: 'op-b', role: 'OPERATOR', siteId: 'site-b' } as AuthUser;
const manager = { id: 'm', role: 'MANAGER', siteId: null } as AuthUser;

function batchRow(over: Record<string, unknown> = {}) {
  return {
    id: BATCH_ID,
    code: 'FSH-20261113-DCK-PTN-0001',
    productId: 'p',
    sourceSiteId: 'site-a',
    currentSiteId: 'site-a',
    storageUnitId: null,
    createdBy: 'op-a',
    createdAt: new Date(),
    capturedAt: new Date(),
    status: 'REGISTERED',
    weightKg: 100,
    currentGrade: null,
    ...over,
  };
}

function makeService(row: Record<string, unknown> | null) {
  const prisma = {
    batch: { findUnique: jest.fn().mockResolvedValue(row) },
    traceEvent: { findMany: jest.fn().mockResolvedValue([]) },
    $transaction: jest.fn(),
  };
  const config = { get: jest.fn().mockResolvedValue(30) };
  const trace = { events: jest.fn().mockResolvedValue([]), verify: jest.fn().mockResolvedValue({ valid: true, count: 0 }) };
  const service = new BatchesService(prisma as never, trace as never, {} as never, {} as never, config as never, {} as never);
  return { service, prisma };
}

async function code(p: Promise<unknown>) {
  try {
    await p;
    return 'OK';
  } catch (e) {
    return e instanceof AppError ? `${e.getStatus()} ${e.code}` : String(e);
  }
}

describe('BatchesService ownership', () => {
  it('operator from another site → 403 FORBIDDEN_SITE', async () => {
    const { service } = makeService(batchRow());
    expect(await code(service.timeline(opB, BATCH_ID))).toBe('403 FORBIDDEN_SITE');
    expect(await code(service.update(opB, BATCH_ID, { weightKg: 90 }))).toBe('403 FORBIDDEN_SITE');
  });

  it('operator of the same site and managers pass', async () => {
    const { service } = makeService(batchRow());
    expect(await code(service.timeline(opA, BATCH_ID))).toBe('OK');
    expect(await code(service.timeline(manager, BATCH_ID))).toBe('OK');
  });

  it('unknown batch → 404', async () => {
    const { service } = makeService(null);
    expect(await code(service.timeline(opA, BATCH_ID))).toBe('404 NOT_FOUND');
  });
});

describe('BatchesService edit window', () => {
  const minutesAgo = (m: number) => new Date(Date.now() - m * 60_000);

  it('31 min after creation → 409 EDIT_WINDOW_CLOSED', async () => {
    const { service, prisma } = makeService(batchRow({ createdAt: minutesAgo(31) }));
    expect(await code(service.update(opA, BATCH_ID, { weightKg: 90 }))).toBe('409 EDIT_WINDOW_CLOSED');
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('29 min after creation → the edit is applied', async () => {
    const { service, prisma } = makeService(batchRow({ createdAt: minutesAgo(29) }));
    prisma.$transaction.mockResolvedValue(batchRow({ weightKg: 90 }));
    expect(await code(service.update(opA, BATCH_ID, { weightKg: 90 }))).toBe('OK');
    expect(prisma.$transaction).toHaveBeenCalledTimes(1);
  });

  it('offline edit: uses the device times (captured 25 min before the edit) even if it syncs much later', async () => {
    const captured = minutesAgo(120);
    const editedAt = new Date(captured.getTime() + 25 * 60_000);
    const { service, prisma } = makeService(batchRow({ createdAt: minutesAgo(5), capturedAt: captured }));
    prisma.$transaction.mockResolvedValue(batchRow());
    expect(await code(service.update(opA, BATCH_ID, { weightKg: 90 }, editedAt))).toBe('OK');
  });

  it('offline edit made 31 min after capture → 409', async () => {
    const captured = minutesAgo(120);
    const editedAt = new Date(captured.getTime() + 31 * 60_000);
    const { service } = makeService(batchRow({ capturedAt: captured }));
    expect(await code(service.update(opA, BATCH_ID, { weightKg: 90 }, editedAt))).toBe('409 EDIT_WINDOW_CLOSED');
  });
});

describe('BatchesService create idempotency', () => {
  it('a retried create with the same client UUID returns the existing batch without writing', async () => {
    const { service, prisma } = makeService(batchRow());
    const r = (await service.create(opA, { id: BATCH_ID } as never, 'dev-1')) as { code: string };
    expect(r.code).toBe('FSH-20261113-DCK-PTN-0001');
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('the same UUID from another user → 409 DUPLICATE', async () => {
    const { service } = makeService(batchRow());
    expect(await code(service.create(opB, { id: BATCH_ID } as never, 'dev-1'))).toBe('409 DUPLICATE');
  });
});
