import { Global, Inject, Injectable, Module, OnModuleInit } from '@nestjs/common';
import { Emitter } from '@socket.io/redis-emitter';
import type Redis from 'ioredis';
import { REDIS } from '../../infra/redis/redis.module';
import { RealtimeGateway } from './realtime.gateway';
import { RealtimeService } from './realtime.service';

/** API process: Socket.IO gateway (with the Redis adapter set up in main.ts). */
@Global()
@Module({ providers: [RealtimeService, RealtimeGateway], exports: [RealtimeService] })
export class RealtimeModule {}

@Injectable()
class EmitterAttacher implements OnModuleInit {
  constructor(
    private readonly realtime: RealtimeService,
    @Inject(REDIS) private readonly redis: Redis,
  ) {}

  onModuleInit() {
    this.realtime.attach(new Emitter(this.redis));
  }
}

/** Worker process: no server; emits go through Redis to the API's Socket.IO adapter. */
@Global()
@Module({ providers: [RealtimeService, EmitterAttacher], exports: [RealtimeService] })
export class RealtimeEmitterModule {}
