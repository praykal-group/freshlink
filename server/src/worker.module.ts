import { Module } from '@nestjs/common';
import { ConfigModule } from './config/config.module';
import { loggerModule } from './common/logger';
import { MlModule } from './infra/ml/ml.module';
import { PrismaModule } from './infra/prisma/prisma.module';
import { ForecastModule } from './modules/forecast/forecast.module';
import { ForecastJob } from './workers/jobs/forecast.job';

/** Background worker process. Kafka consumers and BullMQ jobs join in M8. */
@Module({
  imports: [ConfigModule, loggerModule(), PrismaModule, MlModule, ForecastModule],
  providers: [ForecastJob],
})
export class WorkerModule {}
