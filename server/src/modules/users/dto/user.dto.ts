import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Language, UserRole } from '@prisma/client';
import { Transform } from 'class-transformer';
import { IsEmail, IsEnum, IsOptional, IsString, IsUUID, Length, Matches } from 'class-validator';

const E164 = /^\+[1-9]\d{7,14}$/;

export class CreateUserDto {
  @ApiProperty() @IsString() @Length(2, 120) name: string;

  @ApiProperty({ enum: UserRole }) @IsEnum(UserRole) role: UserRole;

  @ApiPropertyOptional({ example: '+919876543210' })
  @IsOptional()
  @Matches(E164, { message: 'phone must be E.164, e.g. +919876543210' })
  phone?: string;

  @ApiPropertyOptional()
  @IsOptional()
  @IsEmail()
  @Transform(({ value }) => (typeof value === 'string' ? value.trim().toLowerCase() : value))
  email?: string;

  @ApiPropertyOptional() @IsOptional() @IsUUID() siteId?: string;

  @ApiPropertyOptional({ enum: Language }) @IsOptional() @IsEnum(Language) language?: Language;

  @ApiPropertyOptional()
  @IsOptional()
  @Matches(E164, { message: 'emergencyContactPhone must be E.164' })
  emergencyContactPhone?: string;
}

/** Phone and email are identity fields: they change through Supabase, not here (see API docs). */
export class UpdateUserDto {
  @ApiPropertyOptional() @IsOptional() @IsString() @Length(2, 120) name?: string;
  @ApiPropertyOptional({ enum: UserRole }) @IsOptional() @IsEnum(UserRole) role?: UserRole;
  @ApiPropertyOptional() @IsOptional() @IsUUID() siteId?: string;
  @ApiPropertyOptional({ enum: Language }) @IsOptional() @IsEnum(Language) language?: Language;
  @ApiPropertyOptional()
  @IsOptional()
  @Matches(E164, { message: 'emergencyContactPhone must be E.164' })
  emergencyContactPhone?: string;
}
