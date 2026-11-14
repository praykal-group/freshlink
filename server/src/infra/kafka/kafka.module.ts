import { Global, Module } from '@nestjs/common';
import { EventBus } from '../events/event-bus.service';
import { KafkaService } from './kafka.service';

/** Global: every module's EventBus publishes through the same producer. */
@Global()
@Module({ providers: [KafkaService, EventBus], exports: [KafkaService, EventBus] })
export class KafkaModule {}
