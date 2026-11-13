import { Module } from '@nestjs/common';
import { APP_FILTER, APP_GUARD, APP_INTERCEPTOR } from '@nestjs/core';
import { ThrottlerModule } from '@nestjs/throttler';
import { ConfigModule } from './config/config.module';
import { loggerModule } from './common/logger';
import { AllExceptionsFilter } from './common/filters/all-exceptions.filter';
import { DeviceGuard } from './common/guards/device.guard';
import { FlavorRoleGuard } from './common/guards/flavor-role.guard';
import { RolesGuard } from './common/guards/roles.guard';
import { SupabaseAuthGuard } from './common/guards/supabase-auth.guard';
import { UserThrottlerGuard } from './common/guards/user-throttler.guard';
import { VersionGateGuard } from './common/guards/version-gate.guard';
import { AuditInterceptor } from './common/interceptors/audit.interceptor';
import { PrismaModule } from './infra/prisma/prisma.module';
import { AuthModule } from './modules/auth/auth.module';
import { HealthModule } from './modules/health/health.module';
import { HooksModule } from './modules/hooks/hooks.module';
import { MastersModule } from './modules/masters/masters.module';
import { RemoteConfigModule } from './modules/remote-config/remote-config.module';
import { UsersModule } from './modules/users/users.module';

/**
 * HTTP api process. Global guards run in the order listed (Section 6.3):
 * version gate (426) → Supabase JWT + linked user → role/flavor → driver device → @Roles → rate limit.
 */
@Module({
  imports: [
    ConfigModule,
    loggerModule(),
    PrismaModule,
    // In-memory store until Redis joins the stack (D-35).
    ThrottlerModule.forRoot([{ name: 'default', ttl: 60_000, limit: 120 }]),
    AuthModule,
    RemoteConfigModule,
    HealthModule,
    HooksModule,
    UsersModule,
    MastersModule,
  ],
  providers: [
    { provide: APP_FILTER, useClass: AllExceptionsFilter },
    { provide: APP_GUARD, useClass: VersionGateGuard },
    { provide: APP_GUARD, useClass: SupabaseAuthGuard },
    { provide: APP_GUARD, useClass: FlavorRoleGuard },
    { provide: APP_GUARD, useClass: DeviceGuard },
    { provide: APP_GUARD, useClass: RolesGuard },
    { provide: APP_GUARD, useClass: UserThrottlerGuard },
    { provide: APP_INTERCEPTOR, useClass: AuditInterceptor },
  ],
})
export class AppModule {}
