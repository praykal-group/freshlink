import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import type { AppFlavor } from '@prisma/client';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { type AppRequest, parseFlavor } from '../auth/auth-user';
import { TtlCache } from '../cache/ttl-cache';
import { AppError } from '../errors/app-error';

/** Not in Nest's HttpStatus enum. */
const UPGRADE_REQUIRED = 426;
const EXEMPT =/^\/api\/v1\/(auth|app\/updates|health)(\/|\?|$)/;

/**
 * Section 6.1: X-App-Version-Code below the flavor's minSupportedVersionCode → 426 UPGRADE_REQUIRED.
 * The minimum comes from the newest active stable release (synced from GitHub in M15).
 */
@Injectable()
export class VersionGateGuard implements CanActivate {
  private readonly cache = new TtlCache<number>(60_000);

  constructor(private readonly prisma: PrismaService) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const req = ctx.switchToHttp().getRequest<AppRequest>();
    if (EXEMPT.test(req.originalUrl ?? req.url)) return true;
    const flavor = parseFlavor(req.headers['x-app-flavor']);
    const code = Number(req.headers['x-app-version-code']);
    if (!flavor || !Number.isInteger(code)) return true; // hooks, public pages, scripts

    const min = await this.minSupported(flavor);
    if (code < min) {
      throw new AppError('UPGRADE_REQUIRED', 'This app version is no longer supported. Please update.', UPGRADE_REQUIRED, {
        flavor,
        minSupportedVersionCode: min,
      });
    }
    return true;
  }

  async minSupported(flavor: AppFlavor): Promise<number> {
    const hit = this.cache.get(flavor);
    if (hit !== undefined) return hit;
    const latest = await this.prisma.appRelease.findFirst({
      where: { flavor, channel: 'stable', isActive: true },
      orderBy: { versionCode: 'desc' },
      select: { minSupportedCode: true },
    });
    const min = latest?.minSupportedCode ?? 0;
    this.cache.set(flavor, min);
    return min;
  }
}
