import { Body, Controller, Get, Headers, HttpCode, Param, ParseIntPipe, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser, Roles } from '../../common/auth/decorators';
import { PageQuery } from '../../common/pagination';
import { PodService } from '../pod/pod.service';
import { TelemetryService } from '../telemetry/telemetry.service';
import { ArriveDto, AssignTripDto, ListTripsQuery, LoadTripDto, PodDto, PreCheckDto, TelemetryQuery, TripEventDto } from './dto/trip.dto';
import { TripsService } from './trips.service';

const Id = () => Param('id', ParseUUIDPipe);

/** Section 6.4 Trips. Drivers: own trips only (service ownership); operators: load; managers: everything. */
@ApiTags('trips')
@ApiBearerAuth()
@Controller()
export class TripsController {
  constructor(
    private readonly trips: TripsService,
    private readonly pod: PodService,
    private readonly telemetrySvc: TelemetryService,
  ) {}

  @Get('driver/trips/current')
  @Roles('DRIVER')
  current(@CurrentUser() user: AuthUser) {
    return this.trips.currentForDriver(user);
  }

  @Get('driver/trips')
  @Roles('DRIVER')
  history(@CurrentUser() user: AuthUser, @Query() q: PageQuery) {
    return this.trips.historyForDriver(user, q);
  }

  @Get('trips')
  @Roles('MANAGER', 'ADMIN')
  list(@Query() q: ListTripsQuery) {
    return this.trips.list(q);
  }

  @Get('trips/:id')
  @Roles('DRIVER', 'OPERATOR', 'MANAGER', 'ADMIN')
  get(@CurrentUser() user: AuthUser, @Id() id: string) {
    return this.trips.detail(user, id);
  }

  @Get('trips/:id/route')
  @Roles('DRIVER', 'MANAGER', 'ADMIN')
  route(@CurrentUser() user: AuthUser, @Id() id: string) {
    return this.trips.route(user, id);
  }

  @Get('trips/:id/cargo-status')
  @Roles('DRIVER', 'MANAGER', 'ADMIN')
  cargo(@CurrentUser() user: AuthUser, @Id() id: string) {
    return this.trips.cargoStatus(user, id);
  }

  /** Manager chart (Section 10.6): mean per window + the cargo's safe band. */
  @Get('trips/:id/telemetry')
  @Roles('MANAGER', 'ADMIN')
  async telemetry(@Id() id: string, @Query() q: TelemetryQuery) {
    return this.telemetrySvc.tripSeries(id, new Date(q.from), new Date(q.to), q.every ?? '1m');
  }

  @Post('trips/:id/assign')
  @HttpCode(200)
  @Roles('MANAGER', 'ADMIN')
  assign(@CurrentUser() user: AuthUser, @Id() id: string, @Body() dto: AssignTripDto) {
    return this.trips.assign(user, id, dto.driverId, dto.vehicleId);
  }

  @Post('trips/:id/load')
  @HttpCode(200)
  @Roles('OPERATOR', 'ADMIN')
  load(@CurrentUser() user: AuthUser, @Id() id: string, @Body() dto: LoadTripDto) {
    return this.trips.load(user, id, dto.batchIds);
  }

  @Post('trips/:id/pre-check')
  @HttpCode(200)
  @Roles('DRIVER')
  preCheck(@CurrentUser() user: AuthUser, @Id() id: string, @Body() dto: PreCheckDto) {
    return this.trips.preCheck(user, id, dto);
  }

  @Post('trips/:id/start')
  @HttpCode(200)
  @Roles('DRIVER')
  start(@CurrentUser() user: AuthUser, @Id() id: string, @Headers('x-device-id') deviceId?: string) {
    return this.trips.start(user, id, deviceId);
  }

  @Post('trips/:id/events')
  @Roles('DRIVER')
  event(@CurrentUser() user: AuthUser, @Id() id: string, @Body() dto: TripEventDto) {
    return this.trips.recordEvent(user, id, dto);
  }

  @Post('trips/:id/routes/:version/accept')
  @HttpCode(200)
  @Roles('DRIVER')
  accept(@CurrentUser() user: AuthUser, @Id() id: string, @Param('version', ParseIntPipe) version: number) {
    return this.trips.respondRoute(user, id, version, true);
  }

  @Post('trips/:id/routes/:version/decline')
  @HttpCode(200)
  @Roles('DRIVER')
  decline(@CurrentUser() user: AuthUser, @Id() id: string, @Param('version', ParseIntPipe) version: number) {
    return this.trips.respondRoute(user, id, version, false);
  }

  @Post('trips/:id/stops/:stopId/arrive')
  @HttpCode(200)
  @Roles('DRIVER')
  arrive(@CurrentUser() user: AuthUser, @Id() id: string, @Param('stopId', ParseUUIDPipe) stopId: string, @Body() dto: ArriveDto) {
    return this.trips.arrive(user, id, stopId, dto);
  }

  @Post('trips/:id/stops/:stopId/pod')
  @HttpCode(200)
  @Roles('DRIVER')
  submitPod(@CurrentUser() user: AuthUser, @Id() id: string, @Param('stopId', ParseUUIDPipe) stopId: string, @Body() dto: PodDto) {
    return this.pod.submit(user, id, stopId, dto);
  }
}
