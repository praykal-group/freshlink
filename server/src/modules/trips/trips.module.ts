import { Module } from '@nestjs/common';
import { EventBus } from '../../infra/events/event-bus.service';
import { FilesModule } from '../files/files.module';
import { PodService } from '../pod/pod.service';
import { SmsModule } from '../sms/sms.module';
import { StorageModule } from '../storage/storage.module';
import { TripsController } from './trips.controller';
import { TripsService } from './trips.service';

/** Trips + PoD (PoD lives in modules/pod and is wired here because it completes trips). */
@Module({
  imports: [FilesModule, StorageModule, SmsModule],
  controllers: [TripsController],
  providers: [TripsService, PodService, EventBus],
  exports: [TripsService, PodService],
})
export class TripsModule {}
