import { Controller, Get, HttpCode, Param, Post, Res } from '@nestjs/common';
import { ApiExcludeController } from '@nestjs/swagger';
import type { Response } from 'express';
import Handlebars from 'handlebars';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { Public } from '../../common/auth/decorators';
import { AppError } from '../../common/errors/app-error';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { IncidentsService } from '../incidents/incidents.service';
import { OffersService } from './offers.service';

const VIEWS = join(__dirname, '..', '..', '..', 'views');
/** Forms post back to this page only. */
const CSP = "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'";
const ist = (d: Date) => new Date(d.getTime() + 5.5 * 3_600_000).toISOString().replace('T', ' ').slice(0, 16) + ' IST';

type View = { state: 'open' | 'accepted' | 'rejected' | 'gone' | 'missing'; title: string; message?: string; offer?: Record<string, unknown> };

/**
 * Public diversion offer page (W-1, Section 6.4 "Public"): `GET /offer/:token` shows the offer,
 * `POST /offer/:token/accept|reject` answers it once. Expired / reused tokens → 410.
 * No login: the 256-bit token in the SMS link is the credential.
 */
@ApiExcludeController()
@Public()
@Controller('offer')
export class OfferPageController {
  private readonly template = Handlebars.compile(readFileSync(join(VIEWS, 'offer.hbs'), 'utf8'), { strict: false });

  constructor(
    private readonly offers: OffersService,
    private readonly incidents: IncidentsService,
    private readonly prisma: PrismaService,
  ) {}

  @Get(':token')
  async page(@Param('token') token: string, @Res() res: Response) {
    const offer = await this.offers.byToken(token);
    if (!offer) return this.send(res, 404, { state: 'missing', title: 'Offer not found', message: 'This link is not valid.' });
    if (offer.status !== 'SENT' || offer.expiresAt <= new Date()) {
      const status = offer.status === 'SENT' ? 'expired' : offer.status.toLowerCase();
      return this.send(res, 410, { state: 'gone', title: 'Offer closed', message: `This offer has ${status === 'expired' ? 'expired' : `already been ${status}`}.` });
    }
    const batches = await this.prisma.batch.findMany({ where: { id: { in: offer.batchIds } }, include: { product: { select: { name: true } } } });
    const products = [...new Set(batches.map((b) => b.product.name))].join(', ');
    const grades = [...new Set(batches.map((b) => b.currentGrade ?? 'ungraded'))].join(', ');
    const shelf = batches.map((b) => (b.remainingShelfLifeH === null ? null : Number(b.remainingShelfLifeH))).filter((h): h is number => h !== null);
    return this.send(res, 200, {
      state: 'open',
      title: 'Diversion offer',
      offer: {
        token,
        buyer: offer.buyer.name,
        trip: offer.incident.trip.code,
        products,
        grades,
        quantityKg: Number(offer.quantityKg),
        batches: batches.length,
        batchWord: batches.length === 1 ? 'batch' : 'batches',
        discountPct: Number(offer.buyer.discountPct),
        shelfLifeH: shelf.length ? Math.round(Math.min(...shelf) * 10) / 10 : null,
        expiresAt: ist(offer.expiresAt),
      },
    });
  }

  @Post(':token/accept')
  @HttpCode(200)
  accept(@Param('token') token: string, @Res() res: Response) {
    return this.answer(token, true, res);
  }

  @Post(':token/reject')
  @HttpCode(200)
  reject(@Param('token') token: string, @Res() res: Response) {
    return this.answer(token, false, res);
  }

  private async answer(token: string, accept: boolean, res: Response) {
    try {
      await this.incidents.respondOffer(token, accept);
    } catch (e) {
      if (e instanceof AppError && (e.code === 'OFFER_GONE' || e.code === 'NOT_FOUND')) {
        return this.send(res, e.getStatus(), { state: e.code === 'OFFER_GONE' ? 'gone' : 'missing', title: e.code === 'OFFER_GONE' ? 'Offer closed' : 'Offer not found', message: e.message });
      }
      throw e;
    }
    return accept
      ? this.send(res, 200, { state: 'accepted', title: 'Offer accepted', message: 'Thank you. The truck has been sent a new route to you; the driver will call on arrival.' })
      : this.send(res, 200, { state: 'rejected', title: 'Offer rejected', message: 'Thank you for answering. The cargo will be offered elsewhere.' });
  }

  private send(res: Response, status: number, view: View) {
    res.setHeader('Content-Security-Policy', CSP);
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('Cache-Control', 'no-store');
    return res.status(status).type('html').send(this.template({ ...view, [view.state]: true }));
  }
}
