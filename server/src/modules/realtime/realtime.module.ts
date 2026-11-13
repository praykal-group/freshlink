import { Global, Module } from '@nestjs/common';
import { RealtimeGateway } from './realtime.gateway';
import { RealtimeService } from './realtime.service';

/** API process only (the worker imports RealtimeEmitterModule below without the gateway). */
@Global()
@Module({ providers: [RealtimeService, RealtimeGateway], exports: [RealtimeService] })
export class RealtimeModule {}

/** Worker process: same RealtimeService API, no Socket.IO server (emits dropped until M8's Redis adapter). */
@Global()
@Module({ providers: [RealtimeService], exports: [RealtimeService] })
export class RealtimeEmitterModule {}
