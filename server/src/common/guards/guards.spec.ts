import type { ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { UserRole } from '@prisma/client';
import { type AppRequest, APP_FLAVORS, type AuthUser } from '../auth/auth-user';
import { ROLES } from '../auth/decorators';
import { AppError } from '../errors/app-error';
import { FlavorRoleGuard } from './flavor-role.guard';
import { RolesGuard } from './roles.guard';
import { VersionGateGuard } from './version-gate.guard';

const ROLE_LIST: UserRole[] = ['DRIVER', 'OPERATOR', 'MANAGER', 'ADMIN'];

function ctx(req: Partial<AppRequest>, handler: () => void = () => undefined): ExecutionContext {
  return {
    switchToHttp: () => ({ getRequest: () => req }),
    getHandler: () => handler,
    getClass: () => class {},
  } as unknown as ExecutionContext;
}

const user = (role: UserRole) => ({ id: 'u', role }) as AuthUser;

function codeOf(fn: () => unknown): string {
  try {
    fn();
    return 'OK';
  } catch (e) {
    return e instanceof AppError ? e.code : 'OTHER';
  }
}

describe('FlavorRoleGuard (role × flavor matrix)', () => {
  const guard = new FlavorRoleGuard();
  const allowed: Record<string, UserRole[]> = {
    driver: ['DRIVER'],
    operator: ['OPERATOR'],
    manager: ['MANAGER', 'ADMIN'],
    web: ['MANAGER', 'ADMIN'],
  };

  for (const flavor of APP_FLAVORS) {
    for (const role of ROLE_LIST) {
      const expected = allowed[flavor].includes(role) ? 'OK' : 'WRONG_APP_FOR_ROLE';
      it(`${role} on ${flavor} → ${expected}`, () => {
        const req = { user: user(role), headers: { 'x-app-flavor': flavor } } as Partial<AppRequest>;
        expect(codeOf(() => guard.canActivate(ctx(req)))).toBe(expected);
        if (expected === 'OK') expect(req.flavor).toBe(flavor);
      });
    }
  }

  it('requires X-App-Flavor on authenticated routes', () => {
    expect(codeOf(() => guard.canActivate(ctx({ user: user('ADMIN'), headers: {} })))).toBe('MISSING_APP_FLAVOR');
  });

  it('rejects an unknown flavor', () => {
    expect(codeOf(() => guard.canActivate(ctx({ user: user('ADMIN'), headers: { 'x-app-flavor': 'hacker' } })))).toBe(
      'MISSING_APP_FLAVOR',
    );
  });

  it('lets public routes (no user) through', () => {
    expect(guard.canActivate(ctx({ headers: {} }))).toBe(true);
  });
});

describe('RolesGuard (route groups × roles)', () => {
  const reflector = new Reflector();
  const guard = new RolesGuard(reflector);
  // Route groups from Section 6.3 that exist after M3.
  const groups: Record<string, UserRole[] | undefined> = {
    'admin/users (write)': ['ADMIN'],
    'masters (write)': ['ADMIN'],
    'masters (read)': undefined,
    'masters/devices (read)': ['MANAGER', 'ADMIN'],
    'config (read)': ['MANAGER', 'ADMIN'],
    'config (write)': ['ADMIN'],
  };

  for (const [group, roles] of Object.entries(groups)) {
    const handler = () => undefined;
    if (roles) Reflect.defineMetadata(ROLES, roles, handler);
    for (const role of ROLE_LIST) {
      const expected = !roles || roles.includes(role) ? 'OK' : 'FORBIDDEN_ROLE';
      it(`${group}: ${role} → ${expected}`, () => {
        expect(codeOf(() => guard.canActivate(ctx({ user: user(role) }, handler)))).toBe(expected);
      });
    }
  }
});

describe('VersionGateGuard (426)', () => {
  const prisma = { appRelease: { findFirst: jest.fn().mockResolvedValue({ minSupportedCode: 10 }) } };
  const guard = new VersionGateGuard(prisma as never);
  const req = (url: string, code?: number) =>
    ({ originalUrl: url, headers: { 'x-app-flavor': 'driver', ...(code ? { 'x-app-version-code': String(code) } : {}) } }) as Partial<AppRequest>;

  async function codeOfAsync(p: Promise<unknown>) {
    try {
      await p;
      return 'OK';
    } catch (e) {
      return e instanceof AppError ? `${e.getStatus()} ${e.code}` : 'OTHER';
    }
  }

  it('returns 426 below minSupportedVersionCode', async () => {
    expect(await codeOfAsync(guard.canActivate(ctx(req('/api/v1/masters/bundle', 9))))).toBe('426 UPGRADE_REQUIRED');
  });

  it('passes at or above the minimum', async () => {
    expect(await codeOfAsync(guard.canActivate(ctx(req('/api/v1/masters/bundle', 10))))).toBe('OK');
  });

  it.each(['/api/v1/health', '/api/v1/health/ready', '/api/v1/app/updates?flavor=driver', '/api/v1/auth/x'])(
    'exempts %s',
    async (url) => {
      expect(await codeOfAsync(guard.canActivate(ctx(req(url, 1))))).toBe('OK');
    },
  );

  it('ignores requests without a version header (hooks, scripts)', async () => {
    expect(await codeOfAsync(guard.canActivate(ctx(req('/api/v1/masters/bundle'))))).toBe('OK');
  });

  it('caches the minimum per flavor', async () => {
    prisma.appRelease.findFirst.mockClear();
    await guard.canActivate(ctx(req('/api/v1/x', 50)));
    await guard.canActivate(ctx(req('/api/v1/x', 50)));
    expect(prisma.appRelease.findFirst).toHaveBeenCalledTimes(0); // cached from earlier tests
  });
});
