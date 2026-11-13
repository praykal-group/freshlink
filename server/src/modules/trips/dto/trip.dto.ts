import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { PodOutcome, TripStatus } from '@prisma/client';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  ArrayUnique,
  IsArray,
  IsBoolean,
  IsDateString,
  IsEnum,
  IsIn,
  IsLatitude,
  IsLongitude,
  IsNumber,
  IsObject,
  IsOptional,
  IsString,
  IsUUID,
  Length,
  Matches,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';
import { PageQuery } from '../../../common/pagination';

export class AssignTripDto {
  @ApiProperty() @IsUUID() driverId: string;
  @ApiProperty() @IsUUID() vehicleId: string;
}

export class LoadTripDto {
  @ApiProperty({ type: [String] }) @IsArray() @ArrayMinSize(1) @ArrayMaxSize(200) @ArrayUnique() @IsUUID('all', { each: true }) batchIds: string[];
}

export class PreCheckDto {
  @ApiPropertyOptional({ description: 'Client UUID (offline)' }) @IsOptional() @IsUUID() id?: string;
  @ApiProperty() @IsBoolean() reeferOn: boolean;
  @ApiProperty() @IsNumber() @Min(-30) @Max(30) setpointC: number;
  @ApiProperty() @IsBoolean() doorsClosed: boolean;
  @ApiPropertyOptional() @IsOptional() @IsDateString() occurredAt?: string;
}

export const DRIVER_EVENT_TYPES = [
  'INCIDENT_DELAY', 'INCIDENT_BREAKDOWN', 'INCIDENT_ACCIDENT', 'INCIDENT_ROADBLOCK', 'INCIDENT_REEFER_FAULT', 'SOS',
] as const;
export type DriverEventType = (typeof DRIVER_EVENT_TYPES)[number];

/** DA-FR-09 incident (2-tap + optional photo/voice) and DA-FR-14 SOS. Idempotent on the client UUID. */
export class TripEventDto {
  @ApiProperty() @IsUUID() id: string;
  @ApiProperty({ enum: DRIVER_EVENT_TYPES }) @IsIn(DRIVER_EVENT_TYPES) type: DriverEventType;
  @ApiPropertyOptional({ type: Object }) @IsOptional() @IsObject() payload?: Record<string, unknown>;
  @ApiPropertyOptional() @IsOptional() @IsString() @Length(10, 200) photoKey?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @Length(10, 200) voiceKey?: string;
  @ApiPropertyOptional() @IsOptional() @IsLatitude() lat?: number;
  @ApiPropertyOptional() @IsOptional() @IsLongitude() lng?: number;
  @ApiProperty() @IsDateString() occurredAt: string;
}

export class ArriveDto {
  @ApiPropertyOptional() @IsOptional() @IsDateString() arrivedAt?: string;
  @ApiPropertyOptional() @IsOptional() @IsLatitude() lat?: number;
  @ApiPropertyOptional() @IsOptional() @IsLongitude() lng?: number;
}

export class PodItemDto {
  @ApiProperty({ description: 'Client UUID of this PoD row' }) @IsUUID() id: string;
  @ApiProperty() @IsUUID() batchId: string;
  @ApiProperty({ enum: PodOutcome }) @IsEnum(PodOutcome) outcome: PodOutcome;
  @ApiProperty() @IsNumber() @Min(0) @Max(100_000) acceptedKg: number;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(500) reason?: string;
  @ApiProperty({ description: 'Tag UID or batch code scanned from the crate' }) @IsString() @Matches(/^[A-Za-z0-9:_-]{4,128}$/) scannedTagUid: string;
}

/** DA-FR-11/12: one submission per stop: receiver, signature, photo, and an outcome per batch. */
export class PodDto {
  @ApiProperty() @IsString() @Length(2, 120) receiverName: string;
  @ApiProperty() @IsString() @Length(10, 200) signatureKey: string;
  @ApiProperty() @IsString() @Length(10, 200) photoKey: string;
  @ApiProperty() @IsDateString() capturedAt: string;
  @ApiProperty() @IsLatitude() lat: number;
  @ApiProperty() @IsLongitude() lng: number;
  @ApiProperty({ type: [PodItemDto] })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(100)
  @ValidateNested({ each: true })
  @Type(() => PodItemDto)
  items: PodItemDto[];
}

export class ListTripsQuery extends PageQuery {
  @ApiPropertyOptional({ enum: TripStatus }) @IsOptional() @IsEnum(TripStatus) status?: TripStatus;
  @ApiPropertyOptional({ description: 'IST day of plannedStart' }) @IsOptional() @Matches(/^\d{4}-\d{2}-\d{2}$/) date?: string;
}
