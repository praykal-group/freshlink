import { Body, Controller, Get, Headers, HttpStatus, Param, ParseUUIDPipe, Patch, Post, Query, Res } from '@nestjs/common';
import { ApiBearerAuth, ApiQuery, ApiTags } from '@nestjs/swagger';
import type { Response } from 'express';
import { Roles } from '../../common/auth/decorators';
import { AppError } from '../../common/errors/app-error';
import {
  CreateDeviceDto,
  CreateProductDto,
  CreateSiteDto,
  CreateStorageUnitDto,
  CreateVehicleDto,
  UpdateDeviceDto,
  UpdateProductDto,
  UpdateSiteDto,
  UpdateStorageUnitDto,
  UpdateVehicleDto,
} from './dto/masters.dto';
import { MastersService } from './masters.service';

/** Read: every role. Write: ADMIN (Section 6.3). */
@ApiTags('masters')
@ApiBearerAuth()
@Controller('masters')
export class MastersController {
  constructor(private readonly masters: MastersService) {}

  /** Everything an app needs offline, with ETag → 304 when unchanged. */
  @Get('bundle')
  @ApiQuery({ name: 'since', required: false, description: 'ISO timestamp; return only rows changed after it' })
  async bundle(
    @Query('since') sinceRaw: string | undefined,
    @Headers('if-none-match') ifNoneMatch: string | undefined,
    @Res({ passthrough: true }) res: Response,
  ) {
    let since: Date | undefined;
    if (sinceRaw) {
      since = new Date(sinceRaw);
      if (Number.isNaN(since.getTime())) throw new AppError('INVALID_SINCE', 'since must be an ISO-8601 timestamp');
    }
    const etag = await this.masters.bundleEtag(since);
    res.setHeader('ETag', etag);
    res.setHeader('Cache-Control', 'private, no-cache');
    if (ifNoneMatch && ifNoneMatch.split(',').map((t) => t.trim()).includes(etag)) {
      res.status(HttpStatus.NOT_MODIFIED);
      return undefined;
    }
    return this.masters.bundle(since);
  }

  @Get('products') listProducts() { return this.masters.listProducts(); }
  @Post('products') @Roles('ADMIN') createProduct(@Body() dto: CreateProductDto) { return this.masters.createProduct(dto); }
  @Patch('products/:id') @Roles('ADMIN') updateProduct(@Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateProductDto) {
    return this.masters.updateProduct(id, dto);
  }

  @Get('sites') listSites() { return this.masters.listSites(); }
  @Post('sites') @Roles('ADMIN') createSite(@Body() dto: CreateSiteDto) { return this.masters.createSite(dto); }
  @Patch('sites/:id') @Roles('ADMIN') updateSite(@Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateSiteDto) {
    return this.masters.updateSite(id, dto);
  }

  @Get('storage-units')
  @ApiQuery({ name: 'siteId', required: false })
  listStorageUnits(@Query('siteId') siteId?: string) { return this.masters.listStorageUnits(siteId); }
  @Post('storage-units') @Roles('ADMIN') createStorageUnit(@Body() dto: CreateStorageUnitDto) { return this.masters.createStorageUnit(dto); }
  @Patch('storage-units/:id') @Roles('ADMIN') updateStorageUnit(@Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateStorageUnitDto) {
    return this.masters.updateStorageUnit(id, dto);
  }

  @Get('vehicles') listVehicles() { return this.masters.listVehicles(); }
  @Post('vehicles') @Roles('ADMIN') createVehicle(@Body() dto: CreateVehicleDto) { return this.masters.createVehicle(dto); }
  @Patch('vehicles/:id') @Roles('ADMIN') updateVehicle(@Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateVehicleDto) {
    return this.masters.updateVehicle(id, dto);
  }

  @Get('devices') @Roles('MANAGER', 'ADMIN') listDevices() { return this.masters.listDevices(); }
  @Post('devices') @Roles('ADMIN') createDevice(@Body() dto: CreateDeviceDto) { return this.masters.createDevice(dto); }
  @Patch('devices/:id') @Roles('ADMIN') updateDevice(@Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateDeviceDto) {
    return this.masters.updateDevice(id, dto);
  }
}
