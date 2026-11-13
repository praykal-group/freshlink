import { Module } from '@nestjs/common';
import { OrdersModule } from '../orders/orders.module';
import { IntegrationClientsController, IntegrationsController } from './integrations.controller';

@Module({ imports: [OrdersModule], controllers: [IntegrationsController, IntegrationClientsController] })
export class IntegrationsModule {}
