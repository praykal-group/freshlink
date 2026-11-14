import { Global, Inject, Injectable, Module, OnModuleDestroy } from '@nestjs/common';
import Redis from 'ioredis';
import { AppConfig } from '../../config/config.service';

export const REDIS = Symbol('REDIS');

export function requireEnv<T>(value: T | undefined, name: string): T {
  if (value === undefined || value === null || value === '') throw new Error(`${name} is required for this process`);
  return value;
}

/** Shared ioredis connection (state, caches, metrics). BullMQ opens its own connections. */
@Injectable()
class RedisCloser implements OnModuleDestroy {
  constructor(@Inject(REDIS) private readonly redis: Redis) {}

  async onModuleDestroy() {
    await this.redis.quit().catch(() => undefined);
  }
}

@Global()
@Module({
  providers: [
    {
      provide: REDIS,
      inject: [AppConfig],
      useFactory: (config: AppConfig) => new Redis(requireEnv(config.get('REDIS_URL'), 'REDIS_URL'), { maxRetriesPerRequest: 3, enableReadyCheck: true }),
    },
    RedisCloser,
  ],
  exports: [REDIS],
})
export class RedisModule {}
