import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser, Roles } from '../../common/auth/decorators';
import { IncidentActionDto, ListIncidentsQuery, ResolveIncidentDto } from './dto/incident.dto';
import { IncidentsService } from './incidents.service';

@ApiTags('incidents')
@ApiBearerAuth()
@Roles('MANAGER', 'ADMIN')
@Controller('incidents')
export class IncidentsController {
  constructor(private readonly incidents: IncidentsService) {}

  @Get()
  list(@Query() q: ListIncidentsQuery) {
    return this.incidents.list(q);
  }

  /** With the full decision log and offers. */
  @Get(':id')
  detail(@Param('id', ParseUUIDPipe) id: string) {
    return this.incidents.detail(id);
  }

  @Get(':id/offers')
  offers(@Param('id', ParseUUIDPipe) id: string) {
    return this.incidents.offersFor(id);
  }

  /** Manager override: DRIVER_FIX, DIVERT_BUYER {buyerId}, DIVERT_COLD_STORAGE {buyerId}, RESCUE_PICKUP {rescueTripId}, REPLAN, MANUAL. */
  @Post(':id/action')
  @HttpCode(200)
  action(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: IncidentActionDto) {
    return this.incidents.action(user, id, dto);
  }

  @Post(':id/resolve')
  @HttpCode(200)
  resolve(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: ResolveIncidentDto) {
    return this.incidents.resolve(user, id, dto);
  }
}
