import { Controller, Get, HttpCode, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import { AlertStatus } from '@prisma/client';
import { IsEnum, IsOptional, IsUUID } from 'class-validator';
import type { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser, Roles } from '../../common/auth/decorators';
import { PageQuery } from '../../common/pagination';
import { AlertsService } from './alerts.service';

class AlertsQuery extends PageQuery {
  @ApiPropertyOptional({ enum: AlertStatus }) @IsOptional() @IsEnum(AlertStatus) status?: AlertStatus;
  @ApiPropertyOptional() @IsOptional() @IsUUID() tripId?: string;
}

/** Section 6.4: drivers see and ack their own trips' alerts; managers everything. */
@ApiTags('alerts')
@ApiBearerAuth()
@Controller('alerts')
export class AlertsController {
  constructor(private readonly alerts: AlertsService) {}

  @Get()
  @Roles('DRIVER', 'MANAGER', 'ADMIN')
  list(@CurrentUser() user: AuthUser, @Query() q: AlertsQuery) {
    return this.alerts.list(user, q);
  }

  @Post(':id/ack')
  @HttpCode(200)
  @Roles('DRIVER', 'MANAGER', 'ADMIN')
  ack(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.alerts.ack(user, id);
  }

  @Post(':id/resolve')
  @HttpCode(200)
  @Roles('MANAGER', 'ADMIN')
  resolve(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.alerts.resolve(user, id);
  }
}
