import { Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import { type Consumer, type EachBatchPayload, Kafka, logLevel, type Producer } from 'kafkajs';
import { AppConfig } from '../../config/config.service';
import { requireEnv } from '../redis/redis.module';

export const TOPICS = ['truck-telemetry', 'quality-scans', 'order-transactions', 'alerts'] as const;
export type KafkaTopic = (typeof TOPICS)[number];

/** Section 9.3: 3 partitions, 72 h retention. */
const TOPIC_CONFIG = { numPartitions: 3, replicationFactor: 1, configEntries: [{ name: 'retention.ms', value: String(72 * 3_600_000) }] };

/** One Kafka client per process: an idempotent producer plus consumers per group. */
@Injectable()
export class KafkaService implements OnModuleDestroy {
  private readonly logger = new Logger(KafkaService.name);
  private kafka?: Kafka;
  private producer?: Producer;
  private producerReady?: Promise<Producer>;
  private readonly consumers: Consumer[] = [];
  private topicsReady?: Promise<void>;

  /** Topics exist before the first produce/subscribe (broker auto-create is off). Once per process. */
  private ready(): Promise<void> {
    this.topicsReady ??= this.ensureTopics().catch((e: Error) => {
      this.topicsReady = undefined; // retry on the next call
      throw e;
    });
    return this.topicsReady;
  }

  constructor(private readonly config: AppConfig) {}

  get configured(): boolean {
    return !!this.config.get('KAFKA_BROKERS');
  }

  private client(): Kafka {
    this.kafka ??= new Kafka({
      clientId: `iccms-${process.pid}`,
      brokers: requireEnv(this.config.get('KAFKA_BROKERS'), 'KAFKA_BROKERS').split(',').map((b) => b.trim()),
      logLevel: logLevel.WARN,
      retry: { retries: 8, initialRetryTime: 300 },
    });
    return this.kafka;
  }

  /** Creates the topics if they do not exist (broker auto-create is off). Safe to call often. */
  async ensureTopics(): Promise<void> {
    const admin = this.client().admin();
    await admin.connect();
    try {
      const existing = new Set(await admin.listTopics());
      const missing = TOPICS.filter((t) => !existing.has(t));
      if (missing.length) {
        await admin.createTopics({ topics: missing.map((topic) => ({ topic, ...TOPIC_CONFIG })), waitForLeaders: true });
        this.logger.log({ msg: 'kafka topics created', topics: missing });
      }
    } finally {
      await admin.disconnect();
    }
  }

  private getProducer(): Promise<Producer> {
    this.producerReady ??= (async () => {
      const p = this.client().producer({ idempotent: true, maxInFlightRequests: 5, allowAutoTopicCreation: false });
      await p.connect();
      this.producer = p;
      return p;
    })();
    return this.producerReady;
  }

  /**
   * Creates the topics and connects the idempotent producer now, so the first real packets do not
   * pay for InitProducerId and metadata (measured: the cold first batch took seconds).
   */
  async warmUp(): Promise<void> {
    await this.ready();
    await this.getProducer();
  }

  async send(topic: KafkaTopic, messages: { key: string; value: unknown }[]): Promise<void> {
    if (!messages.length) return;
    await this.ready();
    const p = await this.getProducer();
    await p.send({ topic, acks: -1, messages: messages.map((m) => ({ key: m.key, value: JSON.stringify(m.value) })) });
  }

  /** Starts a consumer group. The handler gets a whole batch; offsets are committed after it resolves. */
  async consume(groupId: string, topic: KafkaTopic, handler: (batch: EachBatchPayload) => Promise<void>): Promise<Consumer> {
    await this.ready();
    const consumer = this.client().consumer({ groupId, sessionTimeout: 30_000, heartbeatInterval: 3_000, maxWaitTimeInMs: 100 });
    await consumer.connect();
    await consumer.subscribe({ topic, fromBeginning: false });
    await consumer.run({ eachBatchAutoResolve: true, autoCommitInterval: 1000, eachBatch: handler });
    this.consumers.push(consumer);
    this.logger.log({ msg: 'kafka consumer started', groupId, topic });
    return consumer;
  }

  async onModuleDestroy() {
    await Promise.all(this.consumers.map((c) => c.disconnect().catch(() => undefined)));
    await this.producer?.disconnect().catch(() => undefined);
  }
}
