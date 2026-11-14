import { Global, Inject, Injectable, Module, OnModuleDestroy } from '@nestjs/common';
import { Queue } from 'bullmq';
import { AppConfig } from '../../config/config.service';
import { requireEnv } from '../redis/redis.module';

/** BullMQ queues (D-06). `alerts`: delayed escalations. `maintenance`: repeatable jobs. */
export const QUEUE_ALERTS = 'alerts';
export const QUEUE_MAINTENANCE = 'maintenance';
export const ALERTS_QUEUE = Symbol('ALERTS_QUEUE');
export const MAINTENANCE_QUEUE = Symbol('MAINTENANCE_QUEUE');

/** BullMQ wants its own connections with maxRetriesPerRequest = null. */
export function bullConnection(url: string) {
  const u = new URL(url);
  return {
    host: u.hostname,
    port: Number(u.port || 6379),
    username: u.username || undefined,
    password: u.password ? decodeURIComponent(u.password) : undefined,
    db: u.pathname && u.pathname !== '/' ? Number(u.pathname.slice(1)) : 0,
    tls: u.protocol === 'rediss:' ? {} : undefined,
    maxRetriesPerRequest: null,
  };
}

@Injectable()
class QueueCloser implements OnModuleDestroy {
  constructor(
    @Inject(ALERTS_QUEUE) private readonly alerts: Queue,
    @Inject(MAINTENANCE_QUEUE) private readonly maintenance: Queue,
  ) {}

  async onModuleDestroy() {
    await Promise.all([this.alerts.close(), this.maintenance.close()]);
  }
}

const queue = (name: string, token: symbol) => ({
  provide: token,
  inject: [AppConfig],
  useFactory: (config: AppConfig) =>
    new Queue(name, {
      connection: bullConnection(requireEnv(config.get('REDIS_URL'), 'REDIS_URL')),
      defaultJobOptions: { removeOnComplete: 1000, removeOnFail: 5000, attempts: 3, backoff: { type: 'exponential', delay: 2000 } },
    }),
});

@Global()
@Module({
  providers: [queue(QUEUE_ALERTS, ALERTS_QUEUE), queue(QUEUE_MAINTENANCE, MAINTENANCE_QUEUE), QueueCloser],
  exports: [ALERTS_QUEUE, MAINTENANCE_QUEUE],
})
export class QueueModule {}
