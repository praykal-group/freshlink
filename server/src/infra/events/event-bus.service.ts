import { Injectable, Logger } from '@nestjs/common';

export type Topic = 'truck-telemetry' | 'quality-scans' | 'order-transactions' | 'alerts';

/**
 * Kafka producer stub (M4). Same signature the kafkajs producer will have in M8, so callers
 * do not change; until then events are only logged at debug level.
 */
@Injectable()
export class EventBus {
  private readonly logger = new Logger('EventBus');

  async publish(topic: Topic, key: string, value: Record<string, unknown>): Promise<void> {
    this.logger.debug({ msg: 'event (stub, not sent)', topic, key, type: value.type });
  }
}
