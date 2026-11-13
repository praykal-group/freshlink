import { CanActivate, ExecutionContext, HttpStatus, Inject, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { UserDirectory } from '../../modules/auth/user-directory.service';
import type { AppRequest } from '../auth/auth-user';
import { ALLOW_UNVERIFIED, IS_PUBLIC } from '../auth/decorators';
import { JwtVerifier, TokenVerificationError } from '../auth/jwt-verifier';
import { AppError } from '../errors/app-error';

export const JWT_VERIFIER = Symbol('JWT_VERIFIER');

/**
 * AUTH-05: valid Supabase JWT **and** a linked ACTIVE `users` row.
 * Email users with an unverified address only reach @AllowUnverifiedEmail routes (AUTH-03).
 */
@Injectable()
export class SupabaseAuthGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    @Inject(JWT_VERIFIER) private readonly verifier: JwtVerifier,
    private readonly users: UserDirectory,
  ) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const targets = [ctx.getHandler(), ctx.getClass()];
    if (this.reflector.getAllAndOverride<boolean>(IS_PUBLIC, targets)) return true;

    const req = ctx.switchToHttp().getRequest<AppRequest>();
    const header = req.headers.authorization ?? '';
    const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
    if (!token) throw new AppError('UNAUTHORIZED', 'Missing bearer token', HttpStatus.UNAUTHORIZED);

    let claims;
    try {
      claims = await this.verifier.verify(token);
    } catch (e) {
      const expired = e instanceof TokenVerificationError && e.reason === 'EXPIRED';
      throw new AppError(
        expired ? 'TOKEN_EXPIRED' : 'INVALID_TOKEN',
        expired ? 'Access token expired' : 'Invalid access token',
        HttpStatus.UNAUTHORIZED,
      );
    }

    const user = await this.users.bySupabaseUid(claims.sub);
    if (!user || user.status !== 'ACTIVE') {
      throw new AppError('NOT_REGISTERED', 'This account is not registered or is disabled', HttpStatus.FORBIDDEN);
    }

    const emailVerified =
      !!user.emailVerifiedAt ||
      claims.user_metadata?.email_verified === true ||
      claims.app_metadata?.provider === 'google';
    if (
      user.authMethod === 'EMAIL' &&
      !emailVerified &&
      !this.reflector.getAllAndOverride<boolean>(ALLOW_UNVERIFIED, targets)
    ) {
      throw new AppError('EMAIL_NOT_VERIFIED', 'Verify your email address first', HttpStatus.FORBIDDEN);
    }

    req.user = {
      id: user.id,
      supabaseUid: claims.sub,
      role: user.role,
      siteId: user.siteId,
      status: user.status,
      authMethod: user.authMethod,
      email: user.email,
      phone: user.phone,
      emailVerifiedAt: user.emailVerifiedAt,
      claims,
    };
    return true;
  }
}
