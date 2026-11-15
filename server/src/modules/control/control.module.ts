import { Module } from '@nestjs/common';
import { TelemetryModule } from '../telemetry/telemetry.module';
import { ControlController } from './control.controller';
import { ControlService } from './control.service';

@Module({ imports: [TelemetryModule], controllers: [ControlController], providers: [ControlService] })
export class ControlModule {}
