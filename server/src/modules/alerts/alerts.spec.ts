import type { AuthUser } from '../../common/auth/auth-user';
import { AppError } from '../../common/errors/app-error';
import { NotificationsService } from '../notifications/notifications.service';
import { SmsService } from '../sms/sms.service';
import { AlertsService, ESCALATION_JOB } from './alerts.service';

const TRIP = '9a8e6a1c-4b2d-4c3e-9a1b-2c3d4e5f6a7b';

function setup() {
  const store = new Map<string, Record<string, unknown>>();
  const prisma = {
    alert: {
      create: jest.fn(async ({ data }) => {
        const a = { id: 'alert-1', status: 'OPEN', createdAt: new Date(), acknowledgedBy: null, ...data };
        store.set(a.id, a);
        return a;
      }),
      findUnique: jest.fn(async ({ where }) => store.get(where.id) ?? null),
      findUniqueOrThrow: jest.fn(async ({ where }) => store.get(where.id)),
      update: jest.fn(async ({ where, data }) => Object.assign(store.get(where.id) as object, data)),
      updateMany: jest.fn(async ({ where, data }) => {
        const a = store.get(where.id);
        if (!a || a.status !== where.status) return { count: 0 };
        Object.assign(a, data);
        return { count: 1 };
      }),
    },
    trip: { findUnique: jest.fn().mockResolvedValue({ driverId: 'drv-1' }) },
  };
  const notifications = { toDriver: jest.fn().mockResolvedValue([]), toManagers: jest.fn().mockResolvedValue([]) };
  const realtime = { toTrip: jest.fn(), toManagers: jest.fn(), toUser: jest.fn() };
  const config = { get: jest.fn().mockResolvedValue(5) };
  const events = { publish: jest.fn() };
  const sms = new SmsService({ name: 'test', send: jest.fn().mockRejectedValue(new Error('gateway offline')) } as never, { notification: { create: jest.fn() } } as never);
  const queue = { add: jest.fn(), remove: jest.fn().mockResolvedValue(1) };
  const service = new AlertsService(prisma as never, notifications as never, realtime as never, config as never, events as never, sms, queue as never);
  return { service, prisma, notifications, realtime, queue, sms, store };
}

const driver = { id: 'drv-1', role: 'DRIVER' } as AuthUser;
const manager = { id: 'mgr-1', role: 'MANAGER' } as AuthUser;

describe('AlertsService.raise', () => {
  it('critical cargo alert → driver chain + managers + escalation job after ackMinutes', async () => {
    const s = setup();
    await s.service.raise({ type: 'TEMP_EXCURSION', severity: 'CRITICAL', tripId: TRIP, message: 'hot', notifyDriver: true });
    expect(s.notifications.toDriver).toHaveBeenCalledWith('drv-1', expect.objectContaining({ critical: true, alertId: 'alert-1' }));
    expect(s.notifications.toManagers).toHaveBeenCalled();
    expect(s.queue.add).toHaveBeenCalledWith(ESCALATION_JOB, { alertId: 'alert-1' }, expect.objectContaining({ jobId: 'alert-1', delay: 5 * 60_000 }));
    expect(s.realtime.toTrip).toHaveBeenCalledWith(TRIP, 'alert.raised', expect.objectContaining({ type: 'TEMP_EXCURSION' }));
  });

  it('warning → in-app to managers only, no push/email, no escalation', async () => {
    const s = setup();
    await s.service.raise({ type: 'SHOCK', severity: 'WARNING', tripId: TRIP, message: 'bump' });
    expect(s.notifications.toManagers).not.toHaveBeenCalled();
    expect(s.realtime.toManagers).toHaveBeenCalledWith('alert.raised', expect.objectContaining({ type: 'SHOCK' }));
    expect(s.queue.add).not.toHaveBeenCalled();
  });
});

describe('AlertsService ack / escalate (DA-FR-07)', () => {
  it('driver ack stops the escalation job', async () => {
    const s = setup();
    await s.service.raise({ type: 'TEMP_EXCURSION', severity: 'CRITICAL', tripId: TRIP, message: 'hot', notifyDriver: true });
    const acked = await s.service.ack(driver, 'alert-1');
    expect(acked.status).toBe('ACKNOWLEDGED');
    expect(s.queue.remove).toHaveBeenCalledWith('alert-1');
    expect(await s.service.escalate('alert-1')).toBe(false); // job firing late does nothing
  });

  it('no ack → ESCALATED, managers get push + email + SMS', async () => {
    const s = setup();
    await s.service.raise({ type: 'TEMP_EXCURSION', severity: 'CRITICAL', tripId: TRIP, message: 'hot', notifyDriver: true });
    s.notifications.toManagers.mockClear();
    expect(await s.service.escalate('alert-1')).toBe(true);
    expect(s.store.get('alert-1')?.status).toBe('ESCALATED');
    expect(s.notifications.toManagers).toHaveBeenCalledWith(expect.objectContaining({ title: expect.stringContaining('ESCALATED') }), { withSms: true });
  });

  it('another driver cannot ack; managers can resolve', async () => {
    const s = setup();
    await s.service.raise({ type: 'SOS', severity: 'CRITICAL', tripId: TRIP, message: 'help' });
    s.prisma.trip.findUnique.mockResolvedValueOnce({ driverId: 'someone-else' });
    const err = await s.service.ack(driver, 'alert-1').catch((e) => e);
    expect(err).toBeInstanceOf(AppError);
    expect((await s.service.resolve(manager, 'alert-1')).status).toBe('RESOLVED');
  });
});

describe('SMS gateway down (Section 15)', () => {
  it('3 failed sends in a row raise one SMS_GATEWAY_DOWN alert', async () => {
    const s = setup();
    s.service.onModuleInit();
    for (let i = 0; i < 5; i++) await s.sms.send('+919999900011', 'x').catch(() => undefined);
    await new Promise((r) => setImmediate(r));
    const raised = s.prisma.alert.create.mock.calls.map((c) => c[0].data.type);
    expect(raised).toEqual(['SMS_GATEWAY_DOWN']);
  });
});

describe('NotificationsService fallback chain', () => {
  function notif(push: { ok: boolean; error?: string; deadTokens?: string[] }) {
    const prisma = {
      user: {
        findUnique: jest.fn().mockResolvedValue({ phone: '+919999900011' }),
        findMany: jest.fn().mockResolvedValue([
          { id: 'm1', email: 'verified@iccms.test', emailVerifiedAt: new Date(), phone: '+919999900002' },
          { id: 'm2', email: 'unverified@iccms.test', emailVerifiedAt: null, phone: null },
        ]),
      },
      deviceRegistration: { findMany: jest.fn().mockResolvedValue([{ id: 'd', fcmToken: 'tok' }]), updateMany: jest.fn() },
      notification: { create: jest.fn().mockResolvedValue({}) },
    };
    const sms = { send: jest.fn().mockResolvedValue({}) };
    const mail = { send: jest.fn().mockResolvedValue({ ok: true }) };
    const realtime = { toUser: jest.fn(), toManagers: jest.fn() };
    const svc = new NotificationsService(prisma as never, realtime as never, { send: jest.fn().mockResolvedValue(push) } as never, mail as never, sms as never);
    return { svc, prisma, sms, mail };
  }
  const n = { title: 'CRITICAL: temp', body: 'hot', alertId: 'a1', critical: true, event: 'alert.raised' as const };

  it('driver: push delivered → no SMS', async () => {
    const s = notif({ ok: true });
    const out = await s.svc.toDriver('drv-1', n);
    expect(out.map((d) => d.channel)).toEqual(['IN_APP', 'PUSH']);
    expect(s.sms.send).not.toHaveBeenCalled();
  });

  it('driver: push failed → SMS fallback', async () => {
    const s = notif({ ok: false, error: 'PUSH_NOT_CONFIGURED' });
    const out = await s.svc.toDriver('drv-1', n);
    expect(out.map((d) => `${d.channel}:${d.ok}`)).toEqual(['IN_APP:true', 'PUSH:false', 'SMS:true']);
    expect(s.sms.send).toHaveBeenCalledWith('+919999900011', expect.stringContaining('CRITICAL: temp'), expect.objectContaining({ alertId: 'a1' }));
  });

  it('managers: email only to verified addresses (AUTH-04); dead FCM tokens are cleared', async () => {
    const s = notif({ ok: false, error: 'messaging/registration-token-not-registered', deadTokens: ['tok'] });
    await s.svc.toManagers(n);
    expect(s.mail.send).toHaveBeenCalledTimes(1);
    expect(s.mail.send).toHaveBeenCalledWith('verified@iccms.test', expect.any(String), 'hot');
    expect(s.prisma.deviceRegistration.updateMany).toHaveBeenCalledWith({ where: { fcmToken: { in: ['tok'] } }, data: { fcmToken: null } });
    expect(s.sms.send).not.toHaveBeenCalled();
  });
});
