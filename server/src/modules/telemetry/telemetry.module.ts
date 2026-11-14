import { Global, Module } from '@nestjs/common';
import { DeviceContextService } from './device-context.service';
import { TelemetryService } from './telemetry.service';

@Global()
@Module({ providers: [TelemetryService, DeviceContextService], exports: [TelemetryService, DeviceContextService] })
export class TelemetryModule {}
