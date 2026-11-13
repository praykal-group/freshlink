import { Module } from '@nestjs/common';
import { EventBus } from '../../infra/events/event-bus.service';
import { OrdersController } from './orders.controller';
import { OrdersService } from './orders.service';

@Module({ controllers: [OrdersController], providers: [OrdersService, EventBus], exports: [OrdersService] })
export class OrdersModule {}
