import { Global, Module } from '@nestjs/common';
import { AlertsController } from './alerts.controller';
import { AlertsService } from './alerts.service';

@Global()
@Module({ controllers: [AlertsController], providers: [AlertsService], exports: [AlertsService] })
export class AlertsModule {}

/** Worker: same service, no HTTP controller. */
@Global()
@Module({ providers: [AlertsService], exports: [AlertsService] })
export class AlertsCoreModule {}
