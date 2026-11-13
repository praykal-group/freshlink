import { Module } from '@nestjs/common';
import { ConfigModule } from './config/config.module';
import { loggerModule } from './common/logger';
import { PrismaModule } from './infra/prisma/prisma.module';

/** Background worker process. Kafka consumers and BullMQ jobs get registered here from M8. */
@Module({ imports: [ConfigModule, loggerModule(), PrismaModule] })
export class WorkerModule {}
