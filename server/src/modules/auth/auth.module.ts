import { Global, Module } from '@nestjs/common';
import { createRemoteJWKSet } from 'jose';
import { JwtVerifier } from '../../common/auth/jwt-verifier';
import { JWT_VERIFIER } from '../../common/guards/supabase-auth.guard';
import { AppConfig } from '../../config/config.service';
import { SupabaseAdmin } from '../../infra/supabase/supabase-admin.service';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { UserDirectory } from './user-directory.service';

@Global()
@Module({
  controllers: [AuthController],
  providers: [
    AuthService,
    UserDirectory,
    SupabaseAdmin,
    {
      provide: JWT_VERIFIER,
      inject: [AppConfig],
      useFactory: (config: AppConfig) => {
        const base = config.get('SUPABASE_URL');
        const jwksUrl = config.get('SUPABASE_JWKS_URL') ?? `${base.replace(/\/+$/, '')}/auth/v1/.well-known/jwks.json`;
        // createRemoteJWKSet caches keys and refetches on an unknown `kid` (key rotation).
        return new JwtVerifier(createRemoteJWKSet(new URL(jwksUrl), { cooldownDuration: 30_000 }), base);
      },
    },
  ],
  exports: [UserDirectory, SupabaseAdmin, JWT_VERIFIER],
})
export class AuthModule {}
