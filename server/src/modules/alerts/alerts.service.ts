import { HttpStatus, Inject, Injectable, Logger, OnModuleInit, Optional } from '@nestjs/common';
import { type Alert, type AlertSeverity, type AlertStatus, type AlertType, Prisma } from '@prisma/client';
import type { Queue } from 'bullmq';
import type { AuthUser } from '../../common/auth/auth-user';
import { AppError } from '../../common/errors/app-error';
import { afterCursor, type PageQuery, toPage } from '../../common/pagination';
import { minutesToMs } from '../../common/time-scale';
import { EventBus } from '../../infra/events/event-bus.service';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { ALERTS_QUEUE } from '../../infra/queue/queues';
import { NotificationsService } from '../notifications/notifications.service';
import { RealtimeService } from '../realtime/realtime.service';
import { RemoteConfigService } from '../remote-config/remote-config.service';
import { SmsService } from '../sms/sms.service';

export const ESCALATION_JOB = 'alert-escalation';

export interface RaiseInput {
  type: AlertType;
  severity: AlertSeverity;
  message: string;
  tripId?: string | null;
  vehicleId?: string | null;
  batchId?: string | null;
  data?: Record<string, unknown>;
  /** Notify the trip's driver too (critical cargo alerts, DRIVER_FIX). */
  notifyDriver?: boolean;
}

export const alertView = (a: Alert) => a;

/**
 * Alerts (SYN-07, DA-FR-06/07): raise → notify (fallback chain) → escalate after `ackMinutes`
 * without acknowledgement (BullMQ delayed job, survives restarts) → acknowledge / resolve.
 */
@Injectable()
export class AlertsService implements OnModuleInit {
  private readonly logger = new Logger(AlertsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly notifications: NotificationsService,
    private readonly realtime: RealtimeService,
    private readonly config: RemoteConfigService,
    private readonly events: EventBus,
    private readonly sms: SmsService,
    @Optional() @Inject(ALERTS_QUEUE) private readonly queue?: Queue,
  ) {}

  onModuleInit() {
    this.sms.onGatewayDown((streak, lastError) => {
      void this.raise({
        type: 'SMS_GATEWAY_DOWN',
        severity: 'CRITICAL',
        message: `SMS gateway down: ${streak} sends failed in a row`,
        data: { lastError },
      }).catch((e: Error) => this.logger.error(`could not raise SMS_GATEWAY_DOWN: ${e.message}`));
    });
  }

  async raise(input: RaiseInput): Promise<Alert> {
    const alert = await this.prisma.alert.create({
      data: {
        type: input.type,
        severity: input.severity,
        message: input.message,
        tripId: input.tripId ?? null,
        vehicleId: input.vehicleId ?? null,
        batchId: input.batchId ?? null,
        data: (input.data ?? {}) as Prisma.InputJsonValue,
      },
    });
    const payload = { alertId: alert.id, type: alert.type, severity: alert.severity, tripId: alert.tripId, message: alert.message, createdAt: alert.createdAt };
    if (alert.tripId) this.realtime.toTrip(alert.tripId, 'alert.raised', payload);
    await this.events.publish('alerts', alert.id, { ...payload, alertType: alert.type, type: 'ALERT_RAISED' });

    const critical = alert.severity === 'CRITICAL';
    const data: Record<string, string> = alert.tripId ? { tripId: alert.tripId } : {};
    const notice = { title: `${critical ? 'CRITICAL' : 'Warning'}: ${alert.type.replace(/_/g, ' ').toLowerCase()}`, body: alert.message, alertId: alert.id, critical, event: 'alert.raised' as const, data };
    const driverId = input.notifyDriver && alert.tripId ? (await this.prisma.trip.findUnique({ where: { id: alert.tripId }, select: { driverId: true } }))?.driverId : null;
    try {
      if (driverId) await this.notifications.toDriver(driverId, notice);
      // Managers: push + email for critical; in-app only for warnings (Section 6.5).
      if (critical) await this.notifications.toManagers(notice);
      else this.realtime.toManagers('alert.raised', payload);
    } catch (e) {
      this.logger.error({ msg: 'alert notification failed', alertId: alert.id, error: (e as Error).message });
    }

    if (critical && driverId) await this.scheduleEscalation(alert.id);
    return alert;
  }

  /** DA-FR-07: no ack within ackMinutes → escalate. jobId = alert id, so a re-raise cannot double-schedule. */
  private async scheduleEscalation(alertId: string) {
    if (!this.queue) {
      this.logger.warn({ msg: 'no alert queue (REDIS_URL unset): escalation not scheduled', alertId });
      return;
    }
    const ackMinutes = await this.config.get('ackMinutes');
    await this.queue.add(ESCALATION_JOB, { alertId }, { jobId: alertId, delay: minutesToMs(ackMinutes), attempts: 3 });
  }

  /** Job handler: still unacknowledged → ESCALATED + managers by push, email and SMS. */
  async escalate(alertId: string): Promise<boolean> {
    const flipped = await this.prisma.alert.updateMany({ where: { id: alertId, status: 'OPEN' }, data: { status: 'ESCALATED', escalatedAt: new Date() } });
    if (flipped.count !== 1) return false; // acknowledged or resolved in time
    const alert = await this.prisma.alert.findUniqueOrThrow({ where: { id: alertId } });
    const payload = { alertId, status: 'ESCALATED', type: alert.type, tripId: alert.tripId };
    if (alert.tripId) this.realtime.toTrip(alert.tripId, 'alert.updated', payload);
    await this.notifications.toManagers(
      { title: `ESCALATED: ${alert.type.replace(/_/g, ' ').toLowerCase()}`, body: `Not acknowledged by the driver. ${alert.message}`, alertId, critical: true, event: 'alert.updated', data: alert.tripId ? { tripId: alert.tripId } : {} },
      { withSms: true },
    );
    await this.events.publish('alerts', alertId, { type: 'ALERT_ESCALATED', alertId });
    return true;
  }

  /** Driver of the alert's trip, or a manager. Stops the escalation timer. */
  async ack(user: AuthUser, id: string) {
    const alert = await this.prisma.alert.findUnique({ where: { id } });
    if (!alert) throw new AppError('NOT_FOUND', 'Alert not found', HttpStatus.NOT_FOUND);
    if (user.role === 'DRIVER') {
      const trip = alert.tripId ? await this.prisma.trip.findUnique({ where: { id: alert.tripId }, select: { driverId: true } }) : null;
      if (!trip || trip.driverId !== user.id) throw new AppError('FORBIDDEN_TRIP', 'Alert belongs to another trip', HttpStatus.FORBIDDEN);
    }
    if (alert.status === 'ACKNOWLEDGED' || alert.status === 'RESOLVED') return alert; // idempotent (offline ack replay)
    const updated = await this.prisma.alert.update({ where: { id }, data: { status: 'ACKNOWLEDGED', acknowledgedBy: user.id, acknowledgedAt: new Date() } });
    await this.queue?.remove(id).catch(() => undefined);
    this.emitUpdate(updated);
    return updated;
  }

  async resolve(user: AuthUser, id: string) {
    const alert = await this.prisma.alert.findUnique({ where: { id } });
    if (!alert) throw new AppError('NOT_FOUND', 'Alert not found', HttpStatus.NOT_FOUND);
    if (alert.status === 'RESOLVED') return alert;
    const updated = await this.prisma.alert.update({
      where: { id },
      data: { status: 'RESOLVED', resolvedAt: new Date(), ...(alert.acknowledgedBy ? {} : { acknowledgedBy: user.id, acknowledgedAt: new Date() }) },
    });
    await this.queue?.remove(id).catch(() => undefined);
    this.emitUpdate(updated);
    return updated;
  }

  private emitUpdate(a: Alert) {
    const payload = { alertId: a.id, status: a.status, type: a.type, tripId: a.tripId };
    if (a.tripId) this.realtime.toTrip(a.tripId, 'alert.updated', payload);
    this.realtime.toManagers('alert.updated', payload);
  }

  async list(user: AuthUser, q: PageQuery & { status?: AlertStatus; tripId?: string }) {
    const limit = q.limit ?? 20;
    const driverScope: Prisma.AlertWhereInput = user.role === 'DRIVER' ? { trip: { driverId: user.id } } : {};
    const rows = await this.prisma.alert.findMany({
      where: { AND: [driverScope, q.status ? { status: q.status } : {}, q.tripId ? { tripId: q.tripId } : {}, afterCursor(q.cursor) as Prisma.AlertWhereInput] },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
    });
    return toPage(rows, limit);
  }
}
