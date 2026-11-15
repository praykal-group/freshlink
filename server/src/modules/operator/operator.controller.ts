import { Controller, Get, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiQuery, ApiTags } from '@nestjs/swagger';
import type { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser, Roles } from '../../common/auth/decorators';
import { OperatorService } from './operator.service';

@ApiTags('operator')
@ApiBearerAuth()
@Roles('OPERATOR', 'ADMIN')
@Controller('operator')
export class OperatorController {
  constructor(private readonly operator: OperatorService) {}

  /** Home counts for today (IST) at the operator's site. */
  @Get('summary')
  @ApiQuery({ name: 'date', required: false, description: 'YYYY-MM-DD (IST), default today' })
  summary(@CurrentUser() user: AuthUser, @Query('date') date?: string) {
    return this.operator.summary(user, date);
  }

  /** Trips to load today at the operator's depot, with allocated batches (FO-FR-11). */
  @Get('trips')
  @ApiQuery({ name: 'date', required: false, description: 'YYYY-MM-DD (IST), default today' })
  trips(@CurrentUser() user: AuthUser, @Query('date') date?: string) {
    return this.operator.trips(user, date);
  }
}
