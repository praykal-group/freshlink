import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiProperty, ApiTags } from '@nestjs/swagger';
import { Grade } from '@prisma/client';
import { IsEnum, IsString, Length } from 'class-validator';
import type { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser, Roles } from '../../common/auth/decorators';
import { PageQuery } from '../../common/pagination';
import { GradingService } from './grading.service';

class DisputeDto {
  @ApiProperty() @IsString() @Length(3, 500) reason: string;
}

class ResolveDto {
  @ApiProperty({ enum: Grade }) @IsEnum(Grade) grade: Grade;
}

@ApiTags('grading')
@ApiBearerAuth()
@Controller()
export class GradingController {
  constructor(private readonly grading: GradingService) {}

  @Post('batches/:id/grade')
  @HttpCode(200)
  @Roles('OPERATOR', 'ADMIN')
  grade(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.grading.grade(user, id);
  }

  @Post('batches/:id/grade/dispute')
  @HttpCode(200)
  @Roles('OPERATOR', 'ADMIN')
  dispute(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: DisputeDto) {
    return this.grading.dispute(user, id, dto.reason);
  }

  @Post('grades/:id/resolve')
  @HttpCode(200)
  @Roles('MANAGER', 'ADMIN')
  resolve(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string, @Body() dto: ResolveDto) {
    return this.grading.resolve(user, id, dto.grade);
  }

  @Get('grades/disputes')
  @Roles('MANAGER', 'ADMIN')
  disputes(@Query() q: PageQuery) {
    return this.grading.disputes(q);
  }
}
