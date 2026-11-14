import type { INestApplicationContext } from '@nestjs/common';
import { IoAdapter } from '@nestjs/platform-socket.io';
import { createAdapter } from '@socket.io/redis-adapter';
import Redis from 'ioredis';
import type { Server, ServerOptions } from 'socket.io';

/** Socket.IO with the Redis adapter (D-90): rooms work across API instances and the worker's emitter. */
export class RedisIoAdapter extends IoAdapter {
  private adapter?: ReturnType<typeof createAdapter>;

  static async create(app: INestApplicationContext, url: string): Promise<RedisIoAdapter> {
    const io = new RedisIoAdapter(app);
    const pub = new Redis(url);
    const sub = pub.duplicate();
    await Promise.all([pub.ping(), sub.ping()]);
    io.adapter = createAdapter(pub, sub);
    return io;
  }

  createIOServer(port: number, options?: ServerOptions): Server {
    const server = super.createIOServer(port, options) as Server;
    if (this.adapter) server.adapter(this.adapter);
    return server;
  }
}
