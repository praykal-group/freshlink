import { HttpStatus, Injectable, Logger } from '@nestjs/common';
import type { AppFlavor, Language } from '@prisma/client';
import type { AuthUser } from '../../common/auth/auth-user';
import { AppError } from '../../common/errors/app-error';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { SupabaseAdmin } from '../../infra/supabase/supabase-admin.service';
import type { RegisterSessionDto } from './dto/session.dto';
import { UserDirectory } from './user-directory.service';

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly supabase: SupabaseAdmin,
    private readonly users: UserDirectory,
  ) {}

  /** GET /me. Also copies the Supabase email-confirmed timestamp into users.email_verified_at (AUTH-04). */
  async me(user: AuthUser) {
    let emailVerifiedAt = user.emailVerifiedAt;
    const claimEmail = user.claims.email?.trim().toLowerCase();
    if (claimEmail && claimEmail !== user.email) {
      // Email changed in Supabase (secure email change): store it and require re-verification (AUTH-04).
      await this.prisma.user.update({ where: { id: user.id }, data: { email: claimEmail, emailVerifiedAt: null } });
      this.users.invalidate(user.supabaseUid);
      user = { ...user, email: claimEmail, emailVerifiedAt: null };
      emailVerifiedAt = null;
    }
    if (user.email && !emailVerifiedAt) {
      emailVerifiedAt = await this.resolveEmailVerified(user);
      if (emailVerifiedAt) {
        await this.prisma.user.update({ where: { id: user.id }, data: { emailVerifiedAt } });
        this.users.invalidate(user.supabaseUid);
      }
    }
    const row = await this.prisma.user.findUniqueOrThrow({
      where: { id: user.id },
      include: { site: { select: { id: true, code: true, name: true, type: true } } },
    });
    const flags = await this.prisma.appConfig.findUnique({ where: { key: 'featureFlags' } });
    return {
      id: row.id,
      name: row.name,
      role: row.role,
      phone: row.phone,
      email: row.email,
      emailVerified: !!emailVerifiedAt,
      language: row.language,
      site: row.site,
      flags: flags?.value ?? {},
    };
  }

  private async resolveEmailVerified(user: AuthUser): Promise<Date | null> {
    if (user.claims.user_metadata?.email_verified === true || user.claims.app_metadata?.provider === 'google') {
      return new Date();
    }
    if (!this.supabase.configured) return null;
    try {
      return await this.supabase.emailConfirmedAt(user.supabaseUid);
    } catch (e) {
      this.logger.warn(`email verification lookup failed: ${(e as Error).message}`);
      return null;
    }
  }

  /**
   * POST /me/session: this device becomes the only active one for user + flavor (DA-FR-01, AUTH-07).
   * Done in one transaction so the partial unique index (user_id, flavor) WHERE active never trips.
   */
  async registerSession(user: AuthUser, flavor: AppFlavor, dto: RegisterSessionDto) {
    const now = new Date();
    return this.prisma.$transaction(async (tx) => {
      // The same physical device may have been registered to another user before (shared phone).
      await tx.deviceRegistration.updateMany({
        where: { flavor, active: true, OR: [{ userId: user.id }, { deviceId: dto.deviceId }] },
        data: { active: false },
      });
      const reg = await tx.deviceRegistration.upsert({
        where: { deviceId_flavor: { deviceId: dto.deviceId, flavor } },
        update: { userId: user.id, fcmToken: dto.fcmToken, appVersionCode: dto.appVersionCode, active: true, lastSeenAt: now },
        create: {
          userId: user.id,
          deviceId: dto.deviceId,
          flavor,
          fcmToken: dto.fcmToken,
          appVersionCode: dto.appVersionCode,
          active: true,
          lastSeenAt: now,
        },
      });
      return { deviceId: reg.deviceId, flavor: reg.flavor, active: reg.active };
    });
  }

  async setLanguage(user: AuthUser, language: Language) {
    await this.prisma.user.update({ where: { id: user.id }, data: { language } });
    return { language };
  }

  /** POST /me/logout: mark this device inactive. The app also calls supabase.auth.signOut(). */
  async logout(user: AuthUser, flavor: AppFlavor, deviceId: string | undefined) {
    if (!deviceId) throw new AppError('MISSING_DEVICE_ID', 'X-Device-Id header is required', HttpStatus.BAD_REQUEST);
    const { count } = await this.prisma.deviceRegistration.updateMany({
      where: { userId: user.id, flavor, deviceId, active: true },
      data: { active: false },
    });
    return { loggedOut: count > 0 };
  }
}
