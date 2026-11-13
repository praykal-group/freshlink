import { ApiProperty, ApiPropertyOptional, PartialType } from '@nestjs/swagger';
import { BatchStatus, ImageView, TagType } from '@prisma/client';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsDateString,
  IsEnum,
  IsIn,
  IsInt,
  IsLatitude,
  IsLongitude,
  IsNumber,
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

/** Catch/harvest profile (SYN-03). Required: time + weight; the rest depends on fish vs produce. */
export class BatchFieldsDto {
  @ApiProperty() @IsDateString() caughtOrHarvestedAt: string;
  @ApiProperty() @IsNumber() @Min(0.1) @Max(50_000) weightKg: number;
  @ApiPropertyOptional() @IsOptional() @IsString() @Length(1, 40) vesselId?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @Length(1, 60) farmRef?: string;
  @ApiPropertyOptional() @IsOptional() @IsNumber() @Min(0) @Max(5) iceToFishRatio?: number;
  @ApiPropertyOptional() @IsOptional() @IsNumber() @Min(-5) @Max(40) initialCoreTemp?: number;
  @ApiPropertyOptional() @IsOptional() @IsNumber() @Min(0) @Max(10) maturityIndex?: number;
  @ApiPropertyOptional() @IsOptional() @IsNumber() @Min(0) @Max(40) brix?: number;
  @ApiPropertyOptional() @IsOptional() @IsNumber() @Min(-10) @Max(55) fieldTemp?: number;
  @ApiPropertyOptional() @IsOptional() @IsNumber() @Min(0) @Max(100) fieldHumidity?: number;
}

/** Fields an operator may correct (FO-FR-13): all optional. Product and site are never editable. */
export class EditableBatchFieldsDto extends PartialType(BatchFieldsDto) {}

export const EDITABLE_FIELDS = [
  'caughtOrHarvestedAt', 'weightKg', 'vesselId', 'farmRef', 'iceToFishRatio', 'initialCoreTemp',
  'maturityIndex', 'brix', 'fieldTemp', 'fieldHumidity',
] as const;

/** FO-FR-02/03. `id` is generated on the phone so offline creation is idempotent. */
export class CreateBatchDto extends BatchFieldsDto {
  @ApiProperty({ description: 'Client-generated UUID v4' }) @IsUUID('4') id: string;
  @ApiProperty() @IsUUID() productId: string;
  @ApiProperty({ description: 'Original capture time on the device (offline-safe)' }) @IsDateString() capturedAt: string;
  @ApiPropertyOptional() @IsOptional() @IsLatitude() capturedLat?: number;
  @ApiPropertyOptional() @IsOptional() @IsLongitude() capturedLng?: number;
  @ApiPropertyOptional({ description: 'ADMIN only; operators always register at their own site' })
  @IsOptional()
  @IsUUID()
  siteId?: string;
}

export class EditRequestDto {
  @ApiProperty({ type: EditableBatchFieldsDto })
  @ValidateNested()
  @Type(() => EditableBatchFieldsDto)
  changes: EditableBatchFieldsDto;

  @ApiProperty() @IsString() @Length(3, 500) reason: string;
}

export class ReviewDto {
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(500) note?: string;
}

export class AttachTagDto {
  @ApiProperty({ enum: TagType }) @IsEnum(TagType) tagType: TagType;
  /** NFC UID hex, QR payload id or UHF EPC. */
  @ApiProperty() @IsString() @Matches(/^[A-Za-z0-9:_-]{4,128}$/) tagUid: string;
}

export class AttachImageDto {
  @ApiProperty({ enum: ['TOP', 'SIDE', 'CLOSEUP'] }) @IsIn(['TOP', 'SIDE', 'CLOSEUP']) view: ImageView;
  @ApiProperty() @IsString() @Length(10, 200) key: string;
  @ApiProperty() @IsInt() @Min(1) @Max(10_000) width: number;
  @ApiProperty() @IsInt() @Min(1) @Max(10_000) height: number;
  @ApiProperty() @IsDateString() capturedAt: string;
}

export class AssignStorageDto {
  @ApiProperty() @IsUUID() storageUnitId: string;
}

export const RECEIVE_OUTCOMES = ['ACCEPTED', 'PARTIAL', 'REJECTED'] as const;
export const RECEIVE_CONDITIONS = ['GOOD', 'FAIR', 'POOR'] as const;

export class ReceiveDto {
  @ApiProperty({ enum: RECEIVE_OUTCOMES }) @IsIn(RECEIVE_OUTCOMES) outcome: (typeof RECEIVE_OUTCOMES)[number];
  @ApiProperty() @IsNumber() @Min(0) @Max(50_000) acceptedKg: number;
  @ApiProperty({ enum: RECEIVE_CONDITIONS }) @IsIn(RECEIVE_CONDITIONS) condition: (typeof RECEIVE_CONDITIONS)[number];
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(1000) notes?: string;
  @ApiPropertyOptional({ type: [String] })
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(10)
  @IsString({ each: true })
  imageKeys?: string[];
}

export class ListBatchesQuery extends PageQuery {
  @ApiPropertyOptional({ enum: BatchStatus }) @IsOptional() @IsEnum(BatchStatus) status?: BatchStatus;
  @ApiPropertyOptional({ description: 'Batch code fragment or exact tag UID' }) @IsOptional() @IsString() @MaxLength(128) q?: string;
  @ApiPropertyOptional() @IsOptional() @IsUUID() siteId?: string;
}

export class ListEditRequestsQuery extends PageQuery {
  @ApiPropertyOptional({ enum: ['PENDING', 'APPROVED', 'REJECTED'] })
  @IsOptional()
  @IsIn(['PENDING', 'APPROVED', 'REJECTED'])
  status?: 'PENDING' | 'APPROVED' | 'REJECTED';
}
