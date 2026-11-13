import { Module } from '@nestjs/common';
import { BatchesModule } from '../batches/batches.module';
import { TripsModule } from '../trips/trips.module';
import { SyncController } from './sync.controller';
import { SyncService } from './sync.service';

@Module({ imports: [BatchesModule, TripsModule], controllers: [SyncController], providers: [SyncService] })
export class SyncModule {}
