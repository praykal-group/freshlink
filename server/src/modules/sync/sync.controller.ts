import { Body, Controller, Headers, HttpCode, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser } from '../../common/auth/decorators';
import { SyncRequestDto } from './sync.dto';
import { SyncService } from './sync.service';

@ApiTags('sync')
@ApiBearerAuth()
@Controller('sync')
export class SyncController {
  constructor(private readonly sync: SyncService) {}

  /** Always 200 with one result per op; the per-op status says what happened. */
  @Post()
  @HttpCode(200)
  run(@CurrentUser() user: AuthUser, @Body() dto: SyncRequestDto, @Headers('x-device-id') deviceId?: string) {
    return this.sync.process(user, dto.ops, deviceId);
  }
}
