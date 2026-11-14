import { Controller, Get, Param, ParseUUIDPipe, Query, Res } from '@nestjs/common';
import { ApiBearerAuth, ApiQuery, ApiTags } from '@nestjs/swagger';
import type { Response } from 'express';
import Handlebars from 'handlebars';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { Roles } from '../../common/auth/decorators';
import { AppError } from '../../common/errors/app-error';
import { ReportsService } from './reports.service';

const VIEWS = join(__dirname, '..', '..', '..', 'views');
const HTML_CSP = "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'";

function format(f: string | undefined, allowed: string[], fallback: string): string {
  const v = (f ?? fallback).toLowerCase();
  if (!allowed.includes(v)) throw new AppError('VALIDATION_FAILED', `format must be one of ${allowed.join(', ')}`, 422);
  return v;
}

function csv(res: Response, name: string, body: string) {
  res.setHeader('Content-Disposition', `attachment; filename="${name}"`);
  return res.status(200).type('text/csv; charset=utf-8').send(body);
}

@ApiTags('reports')
@ApiBearerAuth()
@Roles('MANAGER', 'ADMIN')
@Controller('reports')
export class ReportsController {
  private readonly compliance = Handlebars.compile(readFileSync(join(VIEWS, 'compliance.hbs'), 'utf8'), { strict: false });

  constructor(private readonly reports: ReportsService) {}

  @Get('batches/:id/compliance')
  @ApiQuery({ name: 'format', required: false, enum: ['html', 'csv', 'json'] })
  async batchCompliance(@Param('id', ParseUUIDPipe) id: string, @Query('format') f: string | undefined, @Res() res: Response) {
    const fmt = format(f, ['html', 'csv', 'json'], 'html');
    const r = await this.reports.compliance(id);
    if (fmt === 'json') return res.status(200).json(r);
    if (fmt === 'csv') return csv(res, `compliance-${r.batch.code}.csv`, this.reports.complianceCsv(r));
    res.setHeader('Content-Security-Policy', HTML_CSP);
    res.setHeader('X-Content-Type-Options', 'nosniff');
    return res.status(200).type('html').send(this.compliance(this.reports.complianceView(r)));
  }

  @Get('traceability')
  @ApiQuery({ name: 'from', required: true }) @ApiQuery({ name: 'to', required: true })
  async traceability(@Query('from') from: string, @Query('to') to: string, @Query('format') f: string | undefined, @Res() res: Response) {
    format(f, ['csv'], 'csv');
    return csv(res, `traceability-${from.slice(0, 10)}-${to.slice(0, 10)}.csv`, await this.reports.traceability(from, to));
  }

  @Get('emissions')
  @ApiQuery({ name: 'from', required: true }) @ApiQuery({ name: 'to', required: true }) @ApiQuery({ name: 'format', required: false, enum: ['json', 'csv'] })
  async emissions(@Query('from') from: string, @Query('to') to: string, @Query('format') f: string | undefined, @Res() res: Response) {
    const fmt = format(f, ['json', 'csv'], 'json');
    const r = await this.reports.emissions(from, to);
    return fmt === 'csv' ? csv(res, `emissions-${from.slice(0, 10)}-${to.slice(0, 10)}.csv`, this.reports.emissionsCsv(r)) : res.status(200).json(r);
  }

  @Get('reefer-health')
  reeferHealth() {
    return this.reports.reeferHealth();
  }
}
