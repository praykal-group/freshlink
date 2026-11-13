import { CanActivate, ExecutionContext, HttpStatus, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { UserRole } from '@prisma/client';
import type { AppRequest } from '../auth/auth-user';
import { ROLES } from '../auth/decorators';
import { AppError } from '../errors/app-error';

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(ctx: ExecutionContext): boolean {
    const roles = this.reflector.getAllAndOverride<UserRole[] | undefined>(ROLES, [ctx.getHandler(), ctx.getClass()]);
    if (!roles?.length) return true;
    const user = ctx.switchToHttp().getRequest<AppRequest>().user;
    if (!user || !roles.includes(user.role)) {
      throw new AppError('FORBIDDEN_ROLE', 'Your role cannot do this', HttpStatus.FORBIDDEN, { required: roles });
    }
    return true;
  }
}
