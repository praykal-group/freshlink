import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsBoolean, IsEnum, IsOptional, IsString, IsUUID, Length } from 'class-validator';
import { PageQuery } from '../../../common/pagination';

export class ListIncidentsQuery extends PageQuery {
  @ApiPropertyOptional({ enum: ['OPEN', 'ACTION_IN_PROGRESS', 'RESOLVED', 'FAILED'] })
  @IsOptional()
  @IsEnum(['OPEN', 'ACTION_IN_PROGRESS', 'RESOLVED', 'FAILED'])
  status?: 'OPEN' | 'ACTION_IN_PROGRESS' | 'RESOLVED' | 'FAILED';
  @ApiPropertyOptional() @IsOptional() @IsUUID() tripId?: string;
}

export const MANUAL_ACTIONS = ['DRIVER_FIX', 'DIVERT_BUYER', 'DIVERT_COLD_STORAGE', 'RESCUE_PICKUP', 'REPLAN', 'MANUAL'] as const;
export type ManualAction = (typeof MANUAL_ACTIONS)[number];

export class IncidentActionDto {
  @ApiProperty({ enum: MANUAL_ACTIONS }) @IsEnum(MANUAL_ACTIONS) action: ManualAction;
  @ApiPropertyOptional() @IsOptional() @IsUUID() buyerId?: string;
  @ApiPropertyOptional() @IsOptional() @IsUUID() rescueTripId?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @Length(1, 500) note?: string;
}

export class ResolveIncidentDto {
  @ApiPropertyOptional() @IsOptional() @IsString() @Length(1, 500) note?: string;
  @ApiPropertyOptional({ default: false, description: 'true = mark FAILED (cargo lost) instead of RESOLVED' })
  @IsOptional()
  @Type(() => Boolean)
  @IsBoolean()
  failed?: boolean;
}
