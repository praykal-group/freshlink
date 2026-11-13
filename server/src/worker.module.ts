import { Module } from '@nestjs/common';
import { ConfigModule } from './config/config.module';
import { loggerModule } from './common/logger';

/** Background worker process. Kafka consumers and BullMQ jobs get registered here from M8. */
@Module({ imports: [ConfigModule, loggerModule()] })
export class WorkerModule {}
