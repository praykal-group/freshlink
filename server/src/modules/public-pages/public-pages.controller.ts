import { Controller, Get, Param, Query, Res } from '@nestjs/common';
import { ApiExcludeController } from '@nestjs/swagger';
import type { Response } from 'express';
import Handlebars from 'handlebars';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { Public } from '../../common/auth/decorators';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { TraceService } from '../trace/trace.service';
import { eventDetail, EVENT_LABELS, istTime } from './trace-view';

/** server/views, from both src/ (ts-node) and dist/ (compiled): three levels up from this folder. */
const VIEWS = join(__dirname, '..', '..', '..', 'views');

const CSP = "default-src 'none'; style-src 'unsafe-inline'; img-src 'self' data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";

/**
 * Public, signed batch trace (SYN-09, D-14). Served at /t/... outside the /api/v1 prefix.
 * Unknown code and bad signature both answer 404 so codes cannot be enumerated.
 */
@ApiExcludeController()
@Public()
@Controller('t')
export class PublicPagesController {
  private readonly traceTemplate = Handlebars.compile(readFileSync(join(VIEWS, 'trace.hbs'), 'utf8'), { strict: false });

  constructor(
    private readonly prisma: PrismaService,
    private readonly trace: TraceService,
  ) {}

  @Get(':code')
  async page(@Param('code') code: string, @Query('s') sig: string, @Res() res: Response) {
    const batch = await this.findSigned(code, sig);
    res.setHeader('Content-Security-Policy', CSP);
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'no-referrer');
    if (!batch) return res.status(404).type('html').send(NOT_FOUND_HTML);

    const [product, origin, events] = await Promise.all([
      this.prisma.product.findUniqueOrThrow({ where: { id: batch.productId } }),
      this.prisma.site.findUniqueOrThrow({ where: { id: batch.sourceSiteId }, select: { name: true, type: true } }),
      this.trace.events(batch.id),
    ]);
    const verdict = await this.trace.verify(batch.id);
    const fish = product.category === 'FISH';
    const html = this.traceTemplate({
      code: batch.code,
      verified: verdict.valid,
      count: verdict.count,
      checkedAt: istTime(new Date()),
      product: { name: product.name, nameHi: product.nameHi, nameMr: product.nameMr },
      origin,
      sourceLabel: fish ? 'Landed at' : 'Harvested at',
      timeLabel: fish ? 'Caught' : 'Harvested',
      caughtOrHarvestedAt: istTime(batch.caughtOrHarvestedAt),
      weightKg: Number(batch.weightKg),
      grade: batch.currentGrade,
      status: batch.status.replace(/_/g, ' ').toLowerCase(),
      // Telemetry summary arrives with the pipeline in M8.
      temperatureNote: 'The cold-chain temperature log is shown here once the batch has travelled in a monitored truck.',
      events: events.map((e) => ({
        label: EVENT_LABELS[e.eventType] ?? e.eventType,
        detail: eventDetail(e.eventType, e.payload),
        when: istTime(e.occurredAt),
      })),
    });
    res.setHeader('Cache-Control', 'no-store');
    return res.status(200).type('html').send(html);
  }

  @Get(':code/verify')
  async verify(@Param('code') code: string, @Query('s') sig: string, @Res() res: Response) {
    const batch = await this.findSigned(code, sig);
    if (!batch) return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Not found' } });
    const verdict = await this.trace.verify(batch.id);
    return res.status(200).json({ code: batch.code, ...verdict, checkedAt: new Date().toISOString() });
  }

  private async findSigned(code: string, sig: string) {
    if (!this.trace.isValidSignature(code, sig)) return null;
    return this.prisma.batch.findUnique({ where: { code } });
  }
}

const NOT_FOUND_HTML = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Not found</title>
<style>body{font:16px system-ui,sans-serif;margin:0;padding:40px 16px;text-align:center;background:#F4F8FA;color:#0F1C24}</style></head>
<body><h1>Batch not found</h1><p>This trace link is not valid. Scan the QR code on the label again.</p></body></html>`;
