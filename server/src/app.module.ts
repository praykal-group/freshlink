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
import { RedisThrottlerStorage } from './common/guards/redis-throttler.storage';
import { InfluxModule } from './infra/influx/influx.module';
import { KafkaModule } from './infra/kafka/kafka.module';
import { PrismaModule } from './infra/prisma/prisma.module';
import { QueueModule } from './infra/queue/queues';
import { REDIS, RedisModule } from './infra/redis/redis.module';
import type Redis from 'ioredis';
import { AlertsModule } from './modules/alerts/alerts.module';
import { BuyersModule } from './modules/buyers/buyers.module';
import { IncidentsModule } from './modules/incidents/incidents.module';
import { OperatorModule } from './modules/operator/operator.module';
import { ControlModule } from './modules/control/control.module';
import { ReportsModule } from './modules/reports/reports.module';
import { NotificationsModule } from './modules/notifications/notifications.module';
import { TelemetryModule } from './modules/telemetry/telemetry.module';
import { AuthModule } from './modules/auth/auth.module';
import { BatchesModule } from './modules/batches/batches.module';
import { FilesModule } from './modules/files/files.module';
import { ForecastModule } from './modules/forecast/forecast.module';
import { IntegrationsModule } from './modules/integrations/integrations.module';
import { OrdersModule } from './modules/orders/orders.module';
import { PlanningModule } from './modules/planning/planning.module';
import { RealtimeModule } from './modules/realtime/realtime.module';
import { TripsModule } from './modules/trips/trips.module';
import { GradingModule } from './modules/grading/grading.module';
import { MlModule } from './infra/ml/ml.module';
import { ShelfLifeModule } from './modules/shelf-life/shelf-life.module';
import { PublicPagesModule } from './modules/public-pages/public-pages.module';
import { SyncModule } from './modules/sync/sync.module';
import { TraceModule } from './modules/trace/trace.module';
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
    RedisModule,
    KafkaModule,
    InfluxModule,
    QueueModule,
    // 120 req/min per user, counted in Redis so every API instance shares the limit (Section 6.1).
    ThrottlerModule.forRootAsync({
      inject: [REDIS],
      useFactory: (redis: Redis) => ({ throttlers: [{ name: 'default', ttl: 60_000, limit: 120 }], storage: new RedisThrottlerStorage(redis) }),
    }),
    AuthModule,
    RemoteConfigModule,
    HealthModule,
    HooksModule,
    UsersModule,
    MastersModule,
    TraceModule,
    FilesModule,
    BatchesModule,
    SyncModule,
    PublicPagesModule,
    MlModule,
    RealtimeModule,
    ShelfLifeModule,
    GradingModule,
    ForecastModule,
    OrdersModule,
    IntegrationsModule,
    PlanningModule,
    TripsModule,
    NotificationsModule,
    AlertsModule,
    TelemetryModule,
    BuyersModule,
    IncidentsModule,
    ReportsModule,
    OperatorModule,
    ControlModule,
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
