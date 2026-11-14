import { HttpStatus, Inject, Injectable, Logger, Optional } from '@nestjs/common';
import type { DiversionOffer } from '@prisma/client';
import type { Queue } from 'bullmq';
import { createHash, randomBytes } from 'node:crypto';
import { AppError } from '../../common/errors/app-error';
import { minutesToMs } from '../../common/time-scale';
import { AppConfig } from '../../config/config.service';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { ALERTS_QUEUE } from '../../infra/queue/queues';
import { RealtimeService } from '../realtime/realtime.service';
import { RemoteConfigService } from '../remote-config/remote-config.service';
import { SmsService } from '../sms/sms.service';

export const OFFER_TIMEOUT_JOB = 'offer-timeout';

export const tokenHash = (token: string) => createHash('sha256').update(token, 'utf8').digest('hex');

export const offerView = (o: DiversionOffer) => {
  const { tokenHash: _hidden, ...rest } = o;
  void _hidden;
  return { ...rest, quantityKg: Number(o.quantityKg) };
};

const istClock = (d: Date) => new Date(d.getTime() + 5.5 * 3_600_000).toISOString().slice(11, 16);

export interface SendOfferInput {
  incidentId: string;
  buyerId: string;
  batchIds: string[];
  quantityKg: number;
  /** "120 kg Rohu (grade B)". */
  cargoText: string;
  etaAt: Date;
}

/**
 * Diversion offers (W-1): a 32-byte random token (only its SHA-256 is stored) sent by SMS as
 * `APP_BASE_URL/offer/<token>`, valid `offerMinutes` (BullMQ timeout job). A token answers once:
 * the status flip is a conditional update, so a reused or expired link gets 410.
 */
@Injectable()
export class OffersService {
  private readonly logger = new Logger(OffersService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly sms: SmsService,
    private readonly config: RemoteConfigService,
    private readonly app: AppConfig,
    private readonly realtime: RealtimeService,
    @Optional() @Inject(ALERTS_QUEUE) private readonly queue?: Queue,
  ) {}

  async send(input: SendOfferInput): Promise<{ offer: DiversionOffer; url: string }> {
    const buyer = await this.prisma.backupBuyer.findUniqueOrThrow({ where: { id: input.buyerId } });
    const minutes = await this.config.get('offerMinutes');
    const token = randomBytes(32).toString('base64url');
    const offer = await this.prisma.diversionOffer.create({
      data: {
        incidentId: input.incidentId,
        buyerId: buyer.id,
        batchIds: input.batchIds,
        quantityKg: input.quantityKg,
        tokenHash: tokenHash(token),
        expiresAt: new Date(Date.now() + minutesToMs(minutes)),
      },
    });
    const url = `${this.app.get('APP_BASE_URL').replace(/\/+$/, '')}/offer/${token}`;
    try {
      await this.sms.send(
        buyer.phone,
        `I-CCMS diversion offer for ${buyer.name}: ${input.cargoText} at ${Number(buyer.discountPct)}% discount, arriving about ${istClock(input.etaAt)} IST. Accept or reject within ${minutes} min: ${url}`,
        { priority: 'alert' },
      );
    } catch (e) {
      // The timeout job still moves on to the next buyer.
      this.logger.error({ msg: 'offer SMS failed', offerId: offer.id, error: (e as Error).message });
    }
    await this.queue
      ?.add(OFFER_TIMEOUT_JOB, { offerId: offer.id }, { jobId: `offer-${offer.id}`, delay: minutesToMs(minutes) })
      .catch((e: Error) => this.logger.error({ msg: 'offer timeout not scheduled', offerId: offer.id, error: e.message }));
    this.emit(offer);
    return { offer, url };
  }

  /** Manager override: the buyer agreed outside the system; stored as an accepted offer without a usable link. */
  async recordAccepted(incidentId: string, buyerId: string, batchIds: string[], quantityKg: number): Promise<DiversionOffer> {
    const now = new Date();
    const offer = await this.prisma.diversionOffer.create({
      data: { incidentId, buyerId, batchIds, quantityKg, tokenHash: tokenHash(randomBytes(32).toString('base64url')), status: 'ACCEPTED', expiresAt: now, respondedAt: now },
    });
    this.emit(offer);
    return offer;
  }

  async byToken(token: string) {
    if (!/^[A-Za-z0-9_-]{43}$/.test(token)) return null;
    return this.prisma.diversionOffer.findUnique({
      where: { tokenHash: tokenHash(token) },
      include: { buyer: true, incident: { include: { trip: { select: { code: true } } } } },
    });
  }

  /** One answer per token: SENT and not expired → ACCEPTED/REJECTED; otherwise 410 (404 if unknown). */
  async claim(token: string, accept: boolean): Promise<DiversionOffer> {
    const offer = await this.byToken(token);
    if (!offer) throw new AppError('NOT_FOUND', 'Offer not found', HttpStatus.NOT_FOUND);
    const now = new Date();
    const flipped = await this.prisma.diversionOffer.updateMany({
      where: { id: offer.id, status: 'SENT', expiresAt: { gt: now } },
      data: { status: accept ? 'ACCEPTED' : 'REJECTED', respondedAt: now },
    });
    if (flipped.count !== 1) {
      const current = await this.prisma.diversionOffer.findUniqueOrThrow({ where: { id: offer.id } });
      throw new AppError('OFFER_GONE', current.status === 'SENT' ? 'This offer has expired' : `This offer was already ${current.status.toLowerCase()}`, HttpStatus.GONE, {
        status: current.status === 'SENT' ? 'EXPIRED' : current.status,
      });
    }
    await this.queue?.remove(`offer-${offer.id}`).catch(() => undefined);
    const updated = await this.prisma.diversionOffer.findUniqueOrThrow({ where: { id: offer.id } });
    this.emit(updated);
    return updated;
  }

  /** Timeout job: still SENT → EXPIRED. */
  async expire(offerId: string): Promise<DiversionOffer | null> {
    const flipped = await this.prisma.diversionOffer.updateMany({ where: { id: offerId, status: 'SENT' }, data: { status: 'EXPIRED', respondedAt: new Date() } });
    if (flipped.count !== 1) return null;
    const offer = await this.prisma.diversionOffer.findUniqueOrThrow({ where: { id: offerId } });
    this.emit(offer);
    return offer;
  }

  /** Manager override or incident closed: open offers are withdrawn. */
  async cancelOpen(incidentId: string): Promise<number> {
    const open = await this.prisma.diversionOffer.findMany({ where: { incidentId, status: 'SENT' }, select: { id: true } });
    if (!open.length) return 0;
    await this.prisma.diversionOffer.updateMany({ where: { id: { in: open.map((o) => o.id) }, status: 'SENT' }, data: { status: 'CANCELLED', respondedAt: new Date() } });
    for (const o of open) await this.queue?.remove(`offer-${o.id}`).catch(() => undefined);
    this.realtime.toManagers('offer.updated', { incidentId, cancelled: open.length });
    return open.length;
  }

  private emit(o: DiversionOffer) {
    this.realtime.toManagers('offer.updated', { offerId: o.id, incidentId: o.incidentId, buyerId: o.buyerId, status: o.status, expiresAt: o.expiresAt });
  }
}
