import { Module } from '@nestjs/common';
import { APP_FILTER } from '@nestjs/core';
import { ConfigModule } from './config/config.module';
import { loggerModule } from './common/logger';
import { AllExceptionsFilter } from './common/filters/all-exceptions.filter';
import { PrismaModule } from './infra/prisma/prisma.module';
import { HealthModule } from './modules/health/health.module';

/** HTTP api process: REST (Socket.IO joins in M7). */
@Module({
  imports: [ConfigModule, loggerModule(), PrismaModule, HealthModule],
  providers: [{ provide: APP_FILTER, useClass: AllExceptionsFilter }],
})
export class AppModule {}
