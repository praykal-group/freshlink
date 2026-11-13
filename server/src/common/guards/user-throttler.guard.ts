import { Injectable } from '@nestjs/common';
import { ThrottlerGuard } from '@nestjs/throttler';
import type { AppRequest } from '../auth/auth-user';

/** 120 req/min per user (falls back to IP for public routes). Section 6.1. */
@Injectable()
export class UserThrottlerGuard extends ThrottlerGuard {
  protected async getTracker(req: Record<string, unknown>): Promise<string> {
    const r = req as unknown as AppRequest;
    return r.user ? `user:${r.user.id}` : `ip:${r.ip}`;
  }
}
