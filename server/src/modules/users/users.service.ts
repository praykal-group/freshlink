import { HttpStatus, Injectable } from '@nestjs/common';
import type { Prisma, User, UserRole } from '@prisma/client';
import { afterCursor, toPage } from '../../common/pagination';
import { AppError } from '../../common/errors/app-error';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { SupabaseAdmin } from '../../infra/supabase/supabase-admin.service';
import { UserDirectory } from '../auth/user-directory.service';
import type { CreateUserDto, ListUsersQuery, UpdateUserDto } from './dto/user.dto';

const FIELD_ROLES: UserRole[] = ['DRIVER', 'OPERATOR'];

@Injectable()
export class UsersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly supabase: SupabaseAdmin,
    private readonly directory: UserDirectory,
  ) {}

  /**
   * AUTH-06: write the RDS row first (INVITED), then create/invite the Supabase user and link it.
   * If Supabase fails the row stays INVITED and POST /admin/users/:id/resend-invite retries.
   */
  /** ADMIN list (M13): newest first, cursor paged; never returns Supabase ids or device rows. */
  async list(q: ListUsersQuery) {
    const limit = q.limit ?? 20;
    const text = q.q?.trim();
    const rows = await this.prisma.user.findMany({
      where: {
        AND: [
          q.role ? { role: q.role } : {},
          q.status ? { status: q.status } : {},
          text ? { OR: [{ name: { contains: text, mode: 'insensitive' } }, { phone: { contains: text } }, { email: { contains: text, mode: 'insensitive' } }] } : {},
          afterCursor(q.cursor) as Prisma.UserWhereInput,
        ],
      },
      select: { id: true, name: true, role: true, status: true, phone: true, email: true, siteId: true, language: true, emergencyContactPhone: true, createdAt: true },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
    });
    return toPage(rows, limit);
  }

  async create(dto: CreateUserDto) {
    if (!dto.phone && !dto.email) throw new AppError('CONTACT_REQUIRED', 'phone or email is required');
    if (FIELD_ROLES.includes(dto.role) && !dto.phone) {
      throw new AppError('PHONE_REQUIRED', `${dto.role} users log in by phone OTP and need a phone`);
    }
    if (FIELD_ROLES.includes(dto.role) && !dto.siteId) {
      throw new AppError('SITE_REQUIRED', `${dto.role} users must be linked to a site`);
    }
    const user = await this.prisma.user.create({
      data: {
        name: dto.name,
        role: dto.role,
        phone: dto.phone,
        email: dto.email,
        siteId: dto.siteId,
        language: dto.language,
        emergencyContactPhone: dto.emergencyContactPhone,
        authMethod: dto.email && !FIELD_ROLES.includes(dto.role) ? 'EMAIL' : 'PHONE',
        status: 'INVITED',
      },
    });
    return this.provision(user);
  }

  async update(id: string, dto: UpdateUserDto) {
    const user = await this.get(id);
    const role = dto.role ?? user.role;
    if (FIELD_ROLES.includes(role) && !user.phone) {
      throw new AppError('PHONE_REQUIRED', `${role} users need a phone`);
    }
    const updated = await this.prisma.user.update({ where: { id }, data: dto });
    this.directory.invalidate(updated.supabaseUid);
    return this.view(updated);
  }

  async setDisabled(id: string, disabled: boolean) {
    const user = await this.get(id);
    if (user.supabaseUid) await this.supabase.setBanned(user.supabaseUid, disabled);
    const status = disabled ? 'DISABLED' : user.supabaseUid ? 'ACTIVE' : 'INVITED';
    const updated = await this.prisma.user.update({ where: { id }, data: { status } });
    if (disabled) {
      await this.prisma.deviceRegistration.updateMany({ where: { userId: id, active: true }, data: { active: false } });
    }
    this.directory.invalidate(user.supabaseUid);
    return this.view(updated);
  }

  /** Re-sends the invite mail, or finishes a provisioning that failed earlier. */
  async resendInvite(id: string) {
    const user = await this.get(id);
    if (user.status === 'DISABLED') throw new AppError('USER_DISABLED', 'Enable the user first', HttpStatus.CONFLICT);
    if (user.supabaseUid && !user.email) {
      throw new AppError('NOTHING_TO_RESEND', 'Phone users log in by OTP; no invite is needed', HttpStatus.CONFLICT);
    }
    if (user.supabaseUid && user.email) {
      await this.supabase.inviteEmail(user.email); // Supabase re-sends the invite for an unconfirmed user
      return this.view(user);
    }
    return this.provision(user);
  }

  private async provision(user: User) {
    const uid = user.email && user.authMethod === 'EMAIL'
      ? await this.supabase.inviteEmail(user.email)
      : await this.supabase.createPhoneUser(user.phone as string);
    const linked = await this.prisma.user.update({
      where: { id: user.id },
      data: { supabaseUid: uid, status: 'ACTIVE' },
    });
    return this.view(linked);
  }

  private async get(id: string): Promise<User> {
    const user = await this.prisma.user.findUnique({ where: { id } });
    if (!user) throw new AppError('NOT_FOUND', 'User not found', HttpStatus.NOT_FOUND);
    return user;
  }

  private view(u: User) {
    return {
      id: u.id,
      name: u.name,
      role: u.role,
      phone: u.phone,
      email: u.email,
      emailVerified: !!u.emailVerifiedAt,
      siteId: u.siteId,
      language: u.language,
      status: u.status,
      linked: !!u.supabaseUid,
      createdAt: u.createdAt,
    };
  }
}
