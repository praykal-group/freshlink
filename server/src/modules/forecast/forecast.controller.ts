import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { ArrayMaxSize, IsArray, IsISO8601, IsOptional, IsUUID, Matches } from 'class-validator';
import { Roles } from '../../common/auth/decorators';
import { AppError } from '../../common/errors/app-error';
import { ForecastService } from './forecast.service';

const DAY = /^\d{4}-\d{2}-\d{2}$/;

class ForecastQuery {
  @ApiPropertyOptional() @IsOptional() @IsUUID() siteId?: string;
  @ApiPropertyOptional() @IsOptional() @IsUUID() productId?: string;
  @ApiProperty({ example: '2026-11-14' }) @Matches(DAY) @IsISO8601({ strict: true }) from: string;
  @ApiProperty({ example: '2026-11-20' }) @Matches(DAY) @IsISO8601({ strict: true }) to: string;
}

class RunDto {
  @ApiPropertyOptional({ description: 'First forecast day (IST); default tomorrow' })
  @IsOptional()
  @Matches(DAY)
  @IsISO8601({ strict: true })
  startDate?: string;

  @ApiPropertyOptional({ type: [String] }) @IsOptional() @IsArray() @ArrayMaxSize(50) @IsUUID('all', { each: true }) siteIds?: string[];
  @ApiPropertyOptional({ type: [String] }) @IsOptional() @IsArray() @ArrayMaxSize(50) @IsUUID('all', { each: true }) productIds?: string[];
}

@ApiTags('forecast')
@ApiBearerAuth()
@Roles('MANAGER', 'ADMIN')
@Controller('forecasts')
export class ForecastController {
  constructor(private readonly forecasts: ForecastService) {}

  @Get()
  query(@Query() q: ForecastQuery) {
    if (q.from > q.to) throw new AppError('INVALID_RANGE', 'from must not be after to');
    const days = (Date.parse(q.to) - Date.parse(q.from)) / 86_400_000;
    if (days > 92) throw new AppError('RANGE_TOO_LONG', 'At most 92 days per request');
    return this.forecasts.query(q);
  }

  /** Async job (Section 6.4). 202 + job id; poll GET /forecasts/jobs/:id. */
  @Post('run')
  @HttpCode(202)
  run(@Body() dto: RunDto) {
    return this.forecasts.start(dto);
  }

  @Get('jobs/:id')
  job(@Param('id', ParseUUIDPipe) id: string) {
    return this.forecasts.job(id);
  }
}
