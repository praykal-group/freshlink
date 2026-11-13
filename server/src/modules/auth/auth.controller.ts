import { Body, Controller, Get, HttpCode, Post, Put, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { AppFlavor } from '@prisma/client';
import type { AppRequest, AuthUser } from '../../common/auth/auth-user';
import { AllowUnverifiedEmail, CurrentUser, SkipDeviceCheck } from '../../common/auth/decorators';
import { AuthService } from './auth.service';
import { RegisterSessionDto, SetLanguageDto } from './dto/session.dto';

/** Login, OTP, refresh and sign-out happen in Supabase from the app; these are the backend-side calls. */
@ApiTags('me')
@ApiBearerAuth()
@Controller('me')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Get()
  @AllowUnverifiedEmail()
  @SkipDeviceCheck()
  me(@CurrentUser() user: AuthUser) {
    return this.auth.me(user);
  }

  @Post('session')
  @HttpCode(200)
  @SkipDeviceCheck()
  session(@CurrentUser() user: AuthUser, @Req() req: AppRequest, @Body() dto: RegisterSessionDto) {
    return this.auth.registerSession(user, req.flavor as AppFlavor, dto);
  }

  @Put('language')
  language(@CurrentUser() user: AuthUser, @Body() dto: SetLanguageDto) {
    return this.auth.setLanguage(user, dto.language);
  }

  @Post('logout')
  @HttpCode(200)
  @AllowUnverifiedEmail()
  @SkipDeviceCheck()
  logout(@CurrentUser() user: AuthUser, @Req() req: AppRequest) {
    const deviceId = req.headers['x-device-id'];
    return this.auth.logout(user, req.flavor as AppFlavor, typeof deviceId === 'string' ? deviceId : undefined);
  }
}
