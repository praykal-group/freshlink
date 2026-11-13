import { Body, Controller, Get, Param, Put } from '@nestjs/common';
import { ApiBearerAuth, ApiBody, ApiTags } from '@nestjs/swagger';
import { IsDefined } from 'class-validator';
import type { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser, Roles } from '../../common/auth/decorators';
import { RemoteConfigService } from './remote-config.service';

class PutConfigDto {
  /** Shape depends on the key; validated by the zod schema in config-keys.ts. */
  @IsDefined() value: unknown;
}

/** Apps read config through /masters/bundle; these routes are for the Control Tower. */
@ApiTags('config')
@ApiBearerAuth()
@Controller('config')
export class RemoteConfigController {
  constructor(private readonly config: RemoteConfigService) {}

  @Get(':key')
  @Roles('MANAGER', 'ADMIN')
  read(@Param('key') key: string) {
    return this.config.read(key);
  }

  @Put(':key')
  @Roles('ADMIN')
  @ApiBody({ schema: { example: { value: 15 } } })
  write(@Param('key') key: string, @Body() dto: PutConfigDto, @CurrentUser() user: AuthUser) {
    return this.config.write(key, dto.value, user.id);
  }
}
