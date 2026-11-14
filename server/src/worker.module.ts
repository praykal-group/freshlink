import { Module } from '@nestjs/common';
import { ConfigModule } from './config/config.module';
import { loggerModule } from './common/logger';
import { InfluxModule } from './infra/influx/influx.module';
import { KafkaModule } from './infra/kafka/kafka.module';
import { MlModule } from './infra/ml/ml.module';
import { PrismaModule } from './infra/prisma/prisma.module';
import { QueueModule } from './infra/queue/queues';
import { RedisModule } from './infra/redis/redis.module';
import { S3Service } from './infra/s3/s3.service';
import { AlertsCoreModule } from './modules/alerts/alerts.module';
import { ForecastModule } from './modules/forecast/forecast.module';
import { NotificationsModule } from './modules/notifications/notifications.module';
import { RealtimeEmitterModule } from './modules/realtime/realtime.module';
import { RemoteConfigCoreModule } from './modules/remote-config/remote-config.module';
import { ShelfLifeModule } from './modules/shelf-life/shelf-life.module';
import { IncidentsCoreModule } from './modules/incidents/incidents.module';
import { TelemetryModule } from './modules/telemetry/telemetry.module';
import { TraceModule } from './modules/trace/trace.module';
import { ExposureAggregator } from './workers/consumers/exposure-aggregator';
import { IncidentEngineConsumer } from './workers/consumers/incident-engine';
import { MqttBridge } from './workers/consumers/mqtt-bridge';
import { TelemetryWriter } from './workers/consumers/telemetry-writer';
import { ThresholdProcessor } from './workers/consumers/threshold-processor';
import { MaintenanceWorker } from './workers/jobs/maintenance.worker';
import { ReeferHealthJob } from './workers/jobs/reefer-health.job';
import { TieringJob } from './workers/jobs/tiering';

/**
 * Worker process (Section 5.1): MQTT bridge, Kafka consumers (telemetry-writer,
 * threshold-processor, exposure-aggregator, incident-engine) and BullMQ jobs. No HTTP listener.
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
    MlModule,
    RemoteConfigCoreModule,
    RealtimeEmitterModule,
    NotificationsModule,
    AlertsCoreModule,
    TraceModule,
    ShelfLifeModule,
    ForecastModule,
    TelemetryModule,
    IncidentsCoreModule,
  ],
  providers: [S3Service, MqttBridge, TelemetryWriter, ThresholdProcessor, ExposureAggregator, IncidentEngineConsumer, TieringJob, ReeferHealthJob, MaintenanceWorker],
})
export class WorkerModule {}
