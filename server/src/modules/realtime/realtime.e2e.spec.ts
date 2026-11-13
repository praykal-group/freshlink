import type { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import type { AddressInfo } from 'node:net';
import { io, type Socket } from 'socket.io-client';
import { JWT_VERIFIER } from '../../common/guards/supabase-auth.guard';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { UserDirectory } from '../auth/user-directory.service';
import { RealtimeGateway } from './realtime.gateway';
import { RealtimeService } from './realtime.service';

// M7: socket events are received by the right rooms only (real Socket.IO server + clients).
const TRIP_A = '9a8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a7b';
const USERS: Record<string, { id: string; role: string; status: string }> = {
  'sub-driver-a': { id: 'drv-a', role: 'DRIVER', status: 'ACTIVE' },
  'sub-driver-b': { id: 'drv-b', role: 'DRIVER', status: 'ACTIVE' },
  'sub-manager': { id: 'mgr', role: 'MANAGER', status: 'ACTIVE' },
};

describe('RealtimeGateway rooms', () => {
  let app: INestApplication;
  let url: string;
  let realtime: RealtimeService;
  const sockets: Socket[] = [];

  beforeAll(async () => {
    const mod = await Test.createTestingModule({
      providers: [
        RealtimeGateway,
        RealtimeService,
        { provide: JWT_VERIFIER, useValue: { verify: async (t: string) => { if (!USERS[t]) throw new Error('bad'); return { sub: t }; } } },
        { provide: UserDirectory, useValue: { bySupabaseUid: async (sub: string) => USERS[sub] ?? null } },
        { provide: PrismaService, useValue: { trip: { findUnique: async ({ where }: { where: { id: string } }) => (where.id === TRIP_A ? { driverId: 'drv-a' } : null) } } },
      ],
    }).compile();
    app = mod.createNestApplication();
    await app.listen(0);
    url = `http://127.0.0.1:${(app.getHttpServer().address() as AddressInfo).port}`;
    realtime = mod.get(RealtimeService);
  });

  afterAll(async () => {
    sockets.forEach((s) => s.disconnect());
    await app.close();
  });

  function connect(token: string, flavor: string): Promise<Socket> {
    return new Promise((resolve, reject) => {
      const s = io(url, { path: '/rt', auth: { token, flavor }, transports: ['websocket'], forceNew: true, reconnection: false });
      sockets.push(s);
      s.once('ready', () => resolve(s));
      s.once('connect_error', reject);
      s.once('disconnect', () => reject(new Error('disconnected')));
    });
  }

  /** Collect every event a socket receives for a short window. */
  function record(s: Socket) {
    const got: string[] = [];
    s.onAny((event: string) => got.push(event));
    return got;
  }
  const settle = () => new Promise((r) => setTimeout(r, 200));

  it('delivers trip, user and manager events only to their rooms', async () => {
    const driverA = await connect('sub-driver-a', 'driver');
    const driverB = await connect('sub-driver-b', 'driver');
    const manager = await connect('sub-manager', 'manager');

    expect(await driverA.emitWithAck('trip.join', { tripId: TRIP_A })).toEqual({ ok: true });
    expect(await driverB.emitWithAck('trip.join', { tripId: TRIP_A })).toEqual({ ok: false, code: 'FORBIDDEN' }); // not his trip
    expect(await manager.emitWithAck('trip.join', { tripId: TRIP_A })).toEqual({ ok: true });

    const a = record(driverA);
    const b = record(driverB);
    const m = record(manager);
    realtime.toTrip(TRIP_A, 'cargo.status', { tripId: TRIP_A });
    realtime.toUser('drv-b', 'trip.updated', { hello: 'b' });
    realtime.toManagers('alert.raised', { type: 'SOS' });
    await settle();

    expect(a).toEqual(['cargo.status']);
    expect(b).toEqual(['trip.updated']);
    expect(m.sort()).toEqual(['alert.raised', 'cargo.status']);
  });

  it('rejects a bad token and a role that does not match the flavor', async () => {
    await expect(connect('nope', 'driver')).rejects.toBeTruthy();
    await expect(connect('sub-driver-a', 'manager')).rejects.toBeTruthy(); // driver on the manager app
  });
});
