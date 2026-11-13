import { Module } from '@nestjs/common';
import { CargoStatusNotifier } from './cargo-status.notifier';
import { ShelfLifeService } from './shelf-life.service';

@Module({ providers: [ShelfLifeService, CargoStatusNotifier], exports: [ShelfLifeService] })
export class ShelfLifeModule {}
