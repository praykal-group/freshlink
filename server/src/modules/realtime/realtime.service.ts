import { Injectable, Logger } from '@nestjs/common';

/** Socket.IO Server (API) or @socket.io/redis-emitter Emitter (worker): both broadcast to rooms. */
export interface RoomBroadcaster {
  to(room: string): { emit(event: string, ...args: unknown[]): unknown };
}

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
 * Thin emitter injected by business services. The API gateway attaches its Socket.IO server; the
 * worker attaches a Redis emitter, which reaches clients connected to any API instance through the
 * Socket.IO Redis adapter (D-90).
 */
@Injectable()
export class RealtimeService {
  private readonly logger = new Logger(RealtimeService.name);
  private server?: RoomBroadcaster;

  attach(server: RoomBroadcaster) {
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
