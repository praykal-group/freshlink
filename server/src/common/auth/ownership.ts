import { HttpStatus } from '@nestjs/common';
import { AppError } from '../errors/app-error';
import type { AuthUser } from './auth-user';

/** Service-level ownership checks (Section 6.3). Managers/admins pass; staff are bound to their site / own records. */
export const Ownership = {
  isPrivileged(user: AuthUser): boolean {
    return user.role === 'MANAGER' || user.role === 'ADMIN';
  },

  /** Operators may only touch records of their own site. */
  assertSite(user: AuthUser, siteId: string | null | undefined): void {
    if (Ownership.isPrivileged(user)) return;
    if (!user.siteId || user.siteId !== siteId) {
      throw new AppError('FORBIDDEN_SITE', 'Record belongs to another site', HttpStatus.FORBIDDEN);
    }
  },

  /** Drivers may only touch their own trips. */
  assertDriver(user: AuthUser, driverId: string | null | undefined): void {
    if (Ownership.isPrivileged(user)) return;
    if (user.role !== 'DRIVER' || user.id !== driverId) {
      throw new AppError('FORBIDDEN_TRIP', 'Trip belongs to another driver', HttpStatus.FORBIDDEN);
    }
  },
};
