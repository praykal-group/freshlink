import { Injectable, Logger } from '@nestjs/common';
import type { NotificationChannel } from '@prisma/client';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { RealtimeService, type RealtimeEvent } from '../realtime/realtime.service';
import { SmsService } from '../sms/sms.service';
import { MailProvider } from './mail.provider';
import { PushProvider, type SendResult } from './push.provider';

export interface Notice {
  title: string;
  body: string;
  alertId?: string;
  critical: boolean;
  /** Socket event used for the in-app channel. */
  event: RealtimeEvent;
  data?: Record<string, string>;
}

export interface Delivery {
  userId: string;
  channel: NotificationChannel;
  ok: boolean;
  error?: string;
}

/**
 * Multi-channel alert delivery (SYN-07, DA-FR-06) with a fallback chain:
 *   driver  → IN_APP + PUSH; SMS when the push fails (no token, FCM error, not configured)
 *   manager → IN_APP + PUSH + EMAIL (only to verified addresses, AUTH-04); SMS on escalation
 * Every attempt is a row in `notifications`.
 */
@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: RealtimeService,
    private readonly push: PushProvider,
    private readonly mail: MailProvider,
    private readonly sms: SmsService,
  ) {}

  private async record(userId: string, channel: NotificationChannel, n: Notice, r: SendResult): Promise<Delivery> {
    await this.prisma.notification
      .create({ data: { userId, alertId: n.alertId, channel, status: r.ok ? 'SENT' : 'FAILED', providerRef: r.providerRef, error: r.error } })
      .catch((e: Error) => this.logger.warn(`notification row not written: ${e.message}`));
    return { userId, channel, ok: r.ok, error: r.error };
  }

  private async pushTo(userId: string, n: Notice): Promise<SendResult> {
    const devices = await this.prisma.deviceRegistration.findMany({ where: { userId, active: true, fcmToken: { not: null } }, select: { id: true, fcmToken: true } });
    const res = await this.push.send(devices.map((d) => d.fcmToken as string), {
      title: n.title,
      body: n.body,
      critical: n.critical,
      data: { ...(n.data ?? {}), ...(n.alertId ? { alertId: n.alertId } : {}), event: n.event },
    });
    if (res.deadTokens?.length) {
      await this.prisma.deviceRegistration.updateMany({ where: { fcmToken: { in: res.deadTokens } }, data: { fcmToken: null } });
    }
    return res;
  }

  private async smsTo(userId: string, phone: string | null, n: Notice): Promise<Delivery> {
    if (!phone) return this.record(userId, 'SMS', n, { ok: false, error: 'NO_PHONE' });
    try {
      // SmsService writes the notifications row itself (it has the provider message id).
      await this.sms.send(phone, `I-CCMS: ${n.title}. ${n.body}`.slice(0, 300), { priority: 'alert', userId, alertId: n.alertId });
      return { userId, channel: 'SMS', ok: true };
    } catch (e) {
      return { userId, channel: 'SMS', ok: false, error: (e as Error).message };
    }
  }

  /** Driver chain: in-app + push, SMS only if the push did not go out. */
  async toDriver(userId: string, n: Notice): Promise<Delivery[]> {
    const user = await this.prisma.user.findUnique({ where: { id: userId }, select: { phone: true } });
    this.realtime.toUser(userId, n.event, { title: n.title, body: n.body, alertId: n.alertId, critical: n.critical, ...(n.data ?? {}) });
    const out = [await this.record(userId, 'IN_APP', n, { ok: true })];
    const push = await this.record(userId, 'PUSH', n, await this.pushTo(userId, n));
    out.push(push);
    if (!push.ok) out.push(await this.smsTo(userId, user?.phone ?? null, n));
    return out;
  }

  /** Manager/admin broadcast: in-app (one room emit) + push + verified email; `withSms` on escalation. */
  async toManagers(n: Notice, opts: { withSms?: boolean } = {}): Promise<Delivery[]> {
    const managers = await this.prisma.user.findMany({
      where: { role: { in: ['MANAGER', 'ADMIN'] }, status: 'ACTIVE' },
      select: { id: true, email: true, emailVerifiedAt: true, phone: true },
    });
    this.realtime.toManagers(n.event, { title: n.title, body: n.body, alertId: n.alertId, critical: n.critical, ...(n.data ?? {}) });
    const out: Delivery[] = [];
    for (const m of managers) {
      out.push(await this.record(m.id, 'IN_APP', n, { ok: true }));
      out.push(await this.record(m.id, 'PUSH', n, await this.pushTo(m.id, n)));
      if (m.email && m.emailVerifiedAt) {
        out.push(await this.record(m.id, 'EMAIL', n, await this.mail.send(m.email, `[I-CCMS] ${n.title}`, n.body)));
      }
      if (opts.withSms) out.push(await this.smsTo(m.id, m.phone, n));
    }
    return out;
  }
}
