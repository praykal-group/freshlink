import { Body, Controller, HttpCode, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiProperty, ApiTags } from '@nestjs/swagger';
import { IsISO8601, IsUUID, Matches } from 'class-validator';
import type { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser, Roles } from '../../common/auth/decorators';
import { PlanningService } from './planning.service';

const DAY = /^\d{4}-\d{2}-\d{2}$/;

class PlanRunDto {
  @ApiProperty({ example: '2026-11-14', description: 'IST day' }) @Matches(DAY) @IsISO8601({ strict: true }) date: string;
}

class PlanRoutesDto extends PlanRunDto {
  @ApiProperty({ description: 'Site where the trucks load (orders whose source is this site)' }) @IsUUID() depotSiteId: string;
}

@ApiTags('planning')
@ApiBearerAuth()
@Roles('MANAGER', 'ADMIN')
@Controller('planning')
export class PlanningController {
  constructor(private readonly planning: PlanningService) {}

  @Post('run')
  @HttpCode(200)
  run(@CurrentUser() user: AuthUser, @Body() dto: PlanRunDto) {
    return this.planning.run(user, dto.date);
  }

  @Post('routes')
  @HttpCode(200)
  routes(@CurrentUser() user: AuthUser, @Body() dto: PlanRoutesDto) {
    return this.planning.buildRoutes(user, dto.date, dto.depotSiteId);
  }
}
