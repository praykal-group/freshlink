import type { AppFlavor, AuthMethod, UserRole, UserStatus } from '@prisma/client';
import type { Request } from 'express';
import type { SupabaseClaims } from './jwt-verifier';

/** The linked `users` row attached to `req.user` by SupabaseAuthGuard. */
export interface AuthUser {
  id: string;
  supabaseUid: string;
  role: UserRole;
  siteId: string | null;
  status: UserStatus;
  authMethod: AuthMethod;
  email: string | null;
  phone: string | null;
  emailVerifiedAt: Date | null;
  claims: SupabaseClaims;
}

/** `req.id` (request id) is already typed by pino-http's IncomingMessage augmentation. */
export interface AppRequest extends Request {
  user?: AuthUser;
  flavor?: AppFlavor;
  rawBody?: Buffer;
}

export const FLAVOR_ROLES: Record<AppFlavor, UserRole[]> = {
  driver: ['DRIVER'],
  operator: ['OPERATOR'],
  manager: ['MANAGER', 'ADMIN'],
  web: ['MANAGER', 'ADMIN'],
};

export const APP_FLAVORS = Object.keys(FLAVOR_ROLES) as AppFlavor[];

export function parseFlavor(value: unknown): AppFlavor | undefined {
  return typeof value === 'string' && (APP_FLAVORS as string[]).includes(value)
    ? (value as AppFlavor)
    : undefined;
}
