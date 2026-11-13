import { Module } from '@nestjs/common';
import { EventBus } from '../../infra/events/event-bus.service';
import { FilesModule } from '../files/files.module';
import { StorageModule } from '../storage/storage.module';
import { BatchesController } from './batches.controller';
import { BatchesService } from './batches.service';

@Module({
  imports: [FilesModule, StorageModule],
  controllers: [BatchesController],
  providers: [BatchesService, EventBus],
  exports: [BatchesService],
})
export class BatchesModule {}
