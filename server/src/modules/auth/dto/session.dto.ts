import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Language } from '@prisma/client';
import { IsEnum, IsInt, IsOptional, IsString, Length, Min } from 'class-validator';

export class RegisterSessionDto {
  @ApiProperty({ example: 'a1b2c3d4-android-id' })
  @IsString()
  @Length(4, 128)
  deviceId: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsString()
  @Length(1, 4096)
  fcmToken?: string;

  @ApiProperty({ example: 1 })
  @IsInt()
  @Min(1)
  appVersionCode: number;
}

export class SetLanguageDto {
  @ApiProperty({ enum: Language })
  @IsEnum(Language)
  language: Language;
}
