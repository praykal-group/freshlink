import { createParamDecorator, ExecutionContext, SetMetadata } from '@nestjs/common';
import type { UserRole } from '@prisma/client';
import type { AppRequest, AuthUser } from './auth-user';

export const IS_PUBLIC = 'iccms:public';
export const ROLES = 'iccms:roles';
export const ALLOW_UNVERIFIED = 'iccms:allowUnverified';
export const SKIP_DEVICE_CHECK = 'iccms:skipDeviceCheck';

/** No JWT required (hooks, public pages, health, update manifest). */
export const Public = () => SetMetadata(IS_PUBLIC, true);

/** Roles allowed on this route (RolesGuard). Without it, any authenticated role passes. */
export const Roles = (...roles: UserRole[]) => SetMetadata(ROLES, roles);

/** Reachable by an email user whose address is not verified yet (AUTH-03/04). */
export const AllowUnverifiedEmail = () => SetMetadata(ALLOW_UNVERIFIED, true);

/** Driver single-device rule does not apply (the route that registers the device). */
export const SkipDeviceCheck = () => SetMetadata(SKIP_DEVICE_CHECK, true);

export const CurrentUser = createParamDecorator((_: unknown, ctx: ExecutionContext): AuthUser => {
  return ctx.switchToHttp().getRequest<AppRequest>().user as AuthUser;
});
