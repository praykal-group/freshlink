import { Controller, Get, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiQuery, ApiTags } from '@nestjs/swagger';
import { Roles } from '../../common/auth/decorators';
import { ControlService } from './control.service';

@ApiTags('control')
@ApiBearerAuth()
@Roles('MANAGER', 'ADMIN')
@Controller('control')
export class ControlController {
  constructor(private readonly control: ControlService) {}

  /** Dashboard KPIs + positions of vehicles on a trip (Section 10.6 #1). */
  @Get('summary')
  summary() {
    return this.control.summary();
  }

  /** Active drivers for trip assignment, with their current trip if any. */
  @Get('drivers')
  drivers() {
    return this.control.drivers();
  }

  /** Published app releases (Section 10.6 #11). */
  @Get('releases')
  @ApiQuery({ name: 'flavor', required: false, enum: ['driver', 'operator', 'manager', 'web'] })
  releases(@Query('flavor') flavor?: string) {
    return this.control.releases(flavor);
  }
}
