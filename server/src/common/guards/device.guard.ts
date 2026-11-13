import { CanActivate, ExecutionContext, HttpStatus, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { PrismaService } from '../../infra/prisma/prisma.service';
import type { AppRequest } from '../auth/auth-user';
import { SKIP_DEVICE_CHECK } from '../auth/decorators';
import { AppError } from '../errors/app-error';

/** DA-FR-01 / AUTH-07: a driver's requests must come from the device registered by POST /me/session. */
@Injectable()
export class DeviceGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly prisma: PrismaService,
  ) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const req = ctx.switchToHttp().getRequest<AppRequest>();
    if (req.user?.role !== 'DRIVER') return true;
    if (this.reflector.getAllAndOverride<boolean>(SKIP_DEVICE_CHECK, [ctx.getHandler(), ctx.getClass()])) return true;

    const deviceId = req.headers['x-device-id'];
    if (typeof deviceId !== 'string' || !deviceId) {
      throw new AppError('MISSING_DEVICE_ID', 'X-Device-Id header is required', HttpStatus.BAD_REQUEST);
    }
    const active = await this.prisma.deviceRegistration.findFirst({
      where: { userId: req.user.id, flavor: 'driver', active: true },
      select: { deviceId: true },
    });
    if (!active) {
      throw new AppError('NO_ACTIVE_SESSION', 'Register this device with POST /me/session first', HttpStatus.CONFLICT);
    }
    if (active.deviceId !== deviceId) {
      throw new AppError('SESSION_ON_OTHER_DEVICE', 'You logged in on another phone', HttpStatus.CONFLICT);
    }
    return true;
  }
}
