import { CanActivate, ExecutionContext, HttpStatus, Injectable } from '@nestjs/common';
import { type AppRequest, FLAVOR_ROLES, parseFlavor } from '../auth/auth-user';
import { AppError } from '../errors/app-error';

/**
 * Role ↔ app flavor (Section 6.2). The header can be faked; RolesGuard + ownership still decide
 * access. This guard exists so a driver logging into the manager app gets a clear error and is signed out.
 */
@Injectable()
export class FlavorRoleGuard implements CanActivate {
  canActivate(ctx: ExecutionContext): boolean {
    const req = ctx.switchToHttp().getRequest<AppRequest>();
    if (!req.user) return true; // public route
    const flavor = parseFlavor(req.headers['x-app-flavor']);
    if (!flavor) {
      throw new AppError('MISSING_APP_FLAVOR', 'X-App-Flavor header is required', HttpStatus.BAD_REQUEST);
    }
    if (!FLAVOR_ROLES[flavor].includes(req.user.role)) {
      throw new AppError('WRONG_APP_FOR_ROLE', `Role ${req.user.role} cannot use the ${flavor} app`, HttpStatus.FORBIDDEN, {
        role: req.user.role,
        flavor,
      });
    }
    req.flavor = flavor;
    return true;
  }
}
