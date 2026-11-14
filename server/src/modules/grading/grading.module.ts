import { Module } from '@nestjs/common';
import { BatchesModule } from '../batches/batches.module';
import { FilesModule } from '../files/files.module';
import { ShelfLifeModule } from '../shelf-life/shelf-life.module';
import { GradingController } from './grading.controller';
import { GradingService } from './grading.service';

@Module({
  imports: [BatchesModule, FilesModule, ShelfLifeModule],
  controllers: [GradingController],
  providers: [GradingService],
})
export class GradingModule {}
