import { Inject, Injectable } from '@nestjs/common';
import type { ThrottlerStorage } from '@nestjs/throttler';
import type Redis from 'ioredis';
import { REDIS } from '../../infra/redis/redis.module';

/** Fixed-window counter in Redis, shared by every API instance (Section 6.1; closes D-35). */
@Injectable()
export class RedisThrottlerStorage implements ThrottlerStorage {
  constructor(@Inject(REDIS) private readonly redis: Redis) {}

  async increment(key: string, ttl: number, limit: number, blockDuration: number, throttlerName: string) {
    const hitsKey = `throttle:${throttlerName}:${key}`;
    const blockKey = `${hitsKey}:blocked`;
    const blockedFor = await this.redis.pttl(blockKey);
    if (blockedFor > 0) return { totalHits: limit + 1, timeToExpire: Math.ceil(blockedFor / 1000), isBlocked: true, timeToBlockExpire: Math.ceil(blockedFor / 1000) };

    const [[, hits], [, pttl]] = (await this.redis.multi().incr(hitsKey).pexpire(hitsKey, ttl, 'NX').pttl(hitsKey).exec()) as [[null, number], [null, number], [null, number]][number][];
    const totalHits = Number(hits);
    const timeToExpire = Math.ceil(Math.max(0, Number(pttl)) / 1000);
    if (totalHits > limit) {
      await this.redis.set(blockKey, '1', 'PX', blockDuration || ttl);
      return { totalHits, timeToExpire, isBlocked: true, timeToBlockExpire: Math.ceil((blockDuration || ttl) / 1000) };
    }
    return { totalHits, timeToExpire, isBlocked: false, timeToBlockExpire: 0 };
  }
}
