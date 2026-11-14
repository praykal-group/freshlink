import { Injectable, Logger, Optional } from '@nestjs/common';
import { KafkaService, type KafkaTopic } from '../kafka/kafka.service';

export type Topic = KafkaTopic;

/**
 * Domain events to Kafka (M8; the M4 stub had the same signature). Without KAFKA_BROKERS (unit
 * tests, partial dev setups) events are only logged. A failed publish is logged, never thrown:
 * the business transaction has already committed and must not be reported as failed.
 */
@Injectable()
export class EventBus {
  private readonly logger = new Logger('EventBus');

  constructor(@Optional() private readonly kafka?: KafkaService) {}

  async publish(topic: Topic, key: string, value: Record<string, unknown>): Promise<void> {
    if (!this.kafka?.configured) {
      this.logger.debug({ msg: 'event (Kafka not configured, not sent)', topic, key, type: value.type });
      return;
    }
    try {
      await this.kafka.send(topic, [{ key, value: { ...value, at: new Date().toISOString() } }]);
    } catch (e) {
      this.logger.error({ msg: 'event publish failed', topic, key, type: value.type, error: (e as Error).message });
    }
  }
}
