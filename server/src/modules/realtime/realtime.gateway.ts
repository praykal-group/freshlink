import { Inject, Logger } from '@nestjs/common';
import {
  ConnectedSocket,
  MessageBody,
  OnGatewayConnection,
  OnGatewayInit,
  SubscribeMessage,
  WebSocketGateway,
} from '@nestjs/websockets';
import type { Server, Socket } from 'socket.io';
import { FLAVOR_ROLES, parseFlavor } from '../../common/auth/auth-user';
import { JwtVerifier } from '../../common/auth/jwt-verifier';
import { JWT_VERIFIER } from '../../common/guards/supabase-auth.guard';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { UserDirectory } from '../auth/user-directory.service';
import { RealtimeService, rooms } from './realtime.service';

interface SocketUser {
  id: string;
  role: string;
}

/**
 * Socket.IO at path /rt (Section 6.4). Auth payload: { token: <Supabase access token>, flavor }.
 * Same checks as HTTP: valid JWT, linked ACTIVE user, role allowed for the flavor. Rooms:
 * user:<id> always, role:manager for MANAGER/ADMIN, trip:<id> on request after an ownership check.
 */
@WebSocketGateway({ path: '/rt', cors: { origin: false } })
export class RealtimeGateway implements OnGatewayInit, OnGatewayConnection {
  private readonly logger = new Logger(RealtimeGateway.name);

  constructor(
    @Inject(JWT_VERIFIER) private readonly verifier: JwtVerifier,
    private readonly users: UserDirectory,
    private readonly prisma: PrismaService,
    private readonly realtime: RealtimeService,
  ) {}

  afterInit(server: Server) {
    this.realtime.attach(server);
  }

  async handleConnection(socket: Socket) {
    try {
      const auth = (socket.handshake.auth ?? {}) as { token?: string; flavor?: string };
      const claims = await this.verifier.verify(String(auth.token ?? ''));
      const user = await this.users.bySupabaseUid(claims.sub);
      const flavor = parseFlavor(auth.flavor);
      if (!user || user.status !== 'ACTIVE' || !flavor || !FLAVOR_ROLES[flavor].includes(user.role)) {
        throw new Error('not allowed');
      }
      socket.data.user = { id: user.id, role: user.role } satisfies SocketUser;
      await socket.join(rooms.user(user.id));
      if (user.role === 'MANAGER' || user.role === 'ADMIN') await socket.join(rooms.managers);
      socket.emit('ready', { userId: user.id });
    } catch (e) {
      this.logger.debug({ msg: 'socket rejected', reason: (e as Error).message });
      socket.emit('error', { code: 'UNAUTHORIZED' });
      socket.disconnect(true);
    }
  }

  /** Join a trip room: managers any trip, drivers only their own. */
  @SubscribeMessage('trip.join')
  async joinTrip(@ConnectedSocket() socket: Socket, @MessageBody() body: { tripId?: string }) {
    const user = socket.data.user as SocketUser | undefined;
    const tripId = typeof body?.tripId === 'string' ? body.tripId : '';
    if (!user || !/^[0-9a-f-]{36}$/i.test(tripId)) return { ok: false, code: 'INVALID' };
    const trip = await this.prisma.trip.findUnique({ where: { id: tripId }, select: { driverId: true } });
    const allowed = trip && (user.role === 'MANAGER' || user.role === 'ADMIN' || trip.driverId === user.id);
    if (!allowed) return { ok: false, code: 'FORBIDDEN' };
    await socket.join(rooms.trip(tripId));
    return { ok: true };
  }

  @SubscribeMessage('trip.leave')
  async leaveTrip(@ConnectedSocket() socket: Socket, @MessageBody() body: { tripId?: string }) {
    if (typeof body?.tripId === 'string') await socket.leave(rooms.trip(body.tripId));
    return { ok: true };
  }
}
