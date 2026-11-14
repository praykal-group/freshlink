import { Module } from '@nestjs/common';
import { ForecastModule } from '../forecast/forecast.module';
import { OrdersModule } from '../orders/orders.module';
import { PlanningController } from './planning.controller';
import { PlanningService } from './planning.service';

@Module({ imports: [ForecastModule, OrdersModule], controllers: [PlanningController], providers: [PlanningService] })
export class PlanningModule {}
