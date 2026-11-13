import { Module } from '@nestjs/common';
import { MlClient } from '../../infra/ml/ml-client.service';
import { CargoStatusNotifier } from './cargo-status.notifier';
import { ShelfLifeService } from './shelf-life.service';

@Module({ providers: [ShelfLifeService, MlClient, CargoStatusNotifier], exports: [ShelfLifeService, MlClient] })
export class ShelfLifeModule {}
