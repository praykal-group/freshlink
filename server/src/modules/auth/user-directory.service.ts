import { Injectable } from '@nestjs/common';
import type { User } from '@prisma/client';
import { TtlCache } from '../../common/cache/ttl-cache';
import { PrismaService } from '../../infra/prisma/prisma.service';

/** Supabase uid → linked `users` row, cached 60 s (Section 6.2). Writers call `invalidate`. */
@Injectable()
export class UserDirectory {
  private readonly cache = new TtlCache<User | null>(60_000);

  constructor(private readonly prisma: PrismaService) {}

  async bySupabaseUid(uid: string): Promise<User | null> {
    const hit = this.cache.get(uid);
    if (hit !== undefined) return hit;
    const user = await this.prisma.user.findUnique({ where: { supabaseUid: uid } });
    this.cache.set(uid, user);
    return user;
  }

  invalidate(uid: string | null | undefined): void {
    if (uid) this.cache.delete(uid);
  }
}
