import { errors, jwtVerify, type JWTPayload, type JWTVerifyGetKey } from 'jose';

export interface SupabaseClaims extends JWTPayload {
  sub: string;
  email?: string;
  phone?: string;
  role?: string;
  aal?: string;
  session_id?: string;
  user_metadata?: { email_verified?: boolean; [k: string]: unknown };
  app_metadata?: { provider?: string; providers?: string[]; [k: string]: unknown };
}

export type VerifyFailure = 'EXPIRED' | 'INVALID';

export class TokenVerificationError extends Error {
  constructor(public readonly reason: VerifyFailure, message: string) {
    super(message);
  }
}

/**
 * Verifies Supabase access tokens (AUTH-05): asymmetric signature via JWKS,
 * `iss = ${SUPABASE_URL}/auth/v1`, `aud = authenticated`, `exp`.
 * The key source is injected so tests can use a local JWKS.
 */
export class JwtVerifier {
  readonly issuer: string;

  constructor(
    private readonly keys: JWTVerifyGetKey,
    supabaseUrl: string,
  ) {
    this.issuer = `${supabaseUrl.replace(/\/+$/, '')}/auth/v1`;
  }

  async verify(token: string): Promise<SupabaseClaims> {
    try {
      const { payload } = await jwtVerify(token, this.keys, {
        issuer: this.issuer,
        audience: 'authenticated',
        algorithms: ['ES256', 'RS256', 'EdDSA'],
        requiredClaims: ['sub', 'exp'],
      });
      return payload as SupabaseClaims;
    } catch (e) {
      if (e instanceof errors.JWTExpired) throw new TokenVerificationError('EXPIRED', 'token expired');
      throw new TokenVerificationError('INVALID', (e as Error).message);
    }
  }
}
