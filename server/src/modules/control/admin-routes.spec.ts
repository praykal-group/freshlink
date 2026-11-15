import type { ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AppError } from '../../common/errors/app-error';
import { RolesGuard } from '../../common/guards/roles.guard';
import { MastersController } from '../masters/masters.controller';
import { RemoteConfigController } from '../remote-config/remote-config.controller';
import { UsersController } from '../users/users.controller';
import { ControlController } from './control.controller';

// M13 "MANAGER cannot open admin screens and the API returns 403 if forced": the real RolesGuard
// on every route behind the console's admin screens (masters writes, users, remote config writes).
type Ctor = { prototype: object; name: string };
function ctx(controller: Ctor, method: string, role: string): ExecutionContext {
  const handler = (controller.prototype as Record<string, unknown>)[method] as () => void;
  return { getHandler: () => handler, getClass: () => controller, switchToHttp: () => ({ getRequest: () => ({ user: { id: 'u', role } }) }) } as unknown as ExecutionContext;
}

function verdict(controller: Ctor, method: string, role: string): string {
  try {
    new RolesGuard(new Reflector()).canActivate(ctx(controller, method, role));
    return 'allowed';
  } catch (e) {
    return e instanceof AppError ? `${e.getStatus()} ${e.code}` : String(e);
  }
}

const ADMIN_ONLY: [Ctor, string][] = [
  [MastersController, 'createProduct'], [MastersController, 'updateProduct'], [MastersController, 'createSite'], [MastersController, 'updateSite'],
  [MastersController, 'createStorageUnit'], [MastersController, 'updateStorageUnit'], [MastersController, 'createVehicle'], [MastersController, 'updateVehicle'],
  [MastersController, 'createDevice'], [MastersController, 'updateDevice'],
  [UsersController, 'list'], [UsersController, 'create'], [UsersController, 'update'], [UsersController, 'disable'], [UsersController, 'enable'], [UsersController, 'resendInvite'],
  [RemoteConfigController, 'write'],
];

describe('admin routes behind the console (M13)', () => {
  it.each(ADMIN_ONLY)('%p.%s: MANAGER → 403 FORBIDDEN_ROLE, ADMIN allowed', (c, m) => {
    expect(typeof (c.prototype as Record<string, unknown>)[m]).toBe('function');
    expect(verdict(c, m, 'MANAGER')).toBe('403 FORBIDDEN_ROLE');
    expect(verdict(c, m, 'ADMIN')).toBe('allowed');
  });

  it('the control-tower reads stay open to managers; drivers and operators are refused', () => {
    for (const m of ['summary', 'drivers', 'releases']) {
      expect(verdict(ControlController, m, 'MANAGER')).toBe('allowed');
      expect(verdict(ControlController, m, 'DRIVER')).toBe('403 FORBIDDEN_ROLE');
      expect(verdict(ControlController, m, 'OPERATOR')).toBe('403 FORBIDDEN_ROLE');
    }
  });
});
