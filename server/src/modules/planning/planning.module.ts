import { Module } from '@nestjs/common';
import { EventBus } from '../../infra/events/event-bus.service';
import { ForecastModule } from '../forecast/forecast.module';
import { OrdersModule } from '../orders/orders.module';
import { PlanningController } from './planning.controller';
import { PlanningService } from './planning.service';

@Module({ imports: [ForecastModule, OrdersModule], controllers: [PlanningController], providers: [PlanningService, EventBus] })
export class PlanningModule {}
