import { Injectable, Logger } from '@nestjs/common';
import type { Server } from 'socket.io';

/** Server events (Section 6.4 Realtime). */
export type RealtimeEvent =
  | 'alert.raised'
  | 'alert.updated'
  | 'cargo.status'
  | 'route.proposed'
  | 'route.updated'
  | 'incident.updated'
  | 'offer.updated'
  | 'trip.updated'
  | 'vehicle.position';

export const rooms = {
  user: (id: string) => `user:${id}`,
  trip: (id: string) => `trip:${id}`,
  managers: 'role:manager',
};

/**
 * Thin emitter injected by business services. The gateway attaches the Socket.IO server at
 * startup; in the worker process (no gateway) emits are no-ops until the M8 Redis adapter.
 */
@Injectable()
export class RealtimeService {
  private readonly logger = new Logger(RealtimeService.name);
  private server?: Server;

  attach(server: Server) {
    this.server = server;
  }

  toUser(userId: string, event: RealtimeEvent, payload: unknown) {
    this.emit(rooms.user(userId), event, payload);
  }

  toTrip(tripId: string, event: RealtimeEvent, payload: unknown) {
    this.emit(rooms.trip(tripId), event, payload);
  }

  toManagers(event: RealtimeEvent, payload: unknown) {
    this.emit(rooms.managers, event, payload);
  }

  private emit(room: string, event: RealtimeEvent, payload: unknown) {
    if (!this.server) {
      this.logger.debug({ msg: 'realtime emit without a gateway (dropped)', room, event });
      return;
    }
    this.server.to(room).emit(event, payload);
  }
}
