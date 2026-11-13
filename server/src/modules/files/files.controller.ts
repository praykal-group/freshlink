import { Body, Controller, Get, HttpCode, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiProperty, ApiTags } from '@nestjs/swagger';
import { IsIn, IsInt, IsString, Length, Min } from 'class-validator';
import type { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser } from '../../common/auth/decorators';
import { FILE_PURPOSES, type FilePurpose } from './file-rules';
import { FilesService } from './files.service';

class PresignDto {
  @ApiProperty({ enum: FILE_PURPOSES }) @IsIn(FILE_PURPOSES) purpose: FilePurpose;
  @ApiProperty({ example: 'image/jpeg' }) @IsString() @Length(3, 100) contentType: string;
  @ApiProperty({ example: 412000 }) @IsInt() @Min(1) sizeBytes: number;
}

@ApiTags('files')
@ApiBearerAuth()
@Controller('files')
export class FilesController {
  constructor(private readonly files: FilesService) {}

  @Post('presign')
  @HttpCode(200)
  presign(@CurrentUser() user: AuthUser, @Body() dto: PresignDto) {
    return this.files.presign(user, dto.purpose, dto.contentType, dto.sizeBytes);
  }

  /** `GET /files/url?key=<key>` (the key contains slashes, so it is a query parameter, not a path segment). */
  @Get('url')
  url(@CurrentUser() user: AuthUser, @Query('key') key: string) {
    return this.files.downloadUrl(user, key ?? '');
  }
}
