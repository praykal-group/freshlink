import { ApiProperty, ApiPropertyOptional, OmitType, PartialType } from '@nestjs/swagger';
import { DeviceStatus, ProductCategory, SiteType, StorageUnitType, VehicleStatus } from '@prisma/client';
import {
  IsBoolean,
  IsEnum,
  IsLatitude,
  IsLongitude,
  IsNumber,
  IsOptional,
  IsPositive,
  IsString,
  IsUUID,
  Length,
  Matches,
  Max,
  Min,
} from 'class-validator';

const CODE = /^[A-Z0-9][A-Z0-9_-]{1,31}$/;
const CODE_MSG = { message: 'code must be 2-32 chars: A-Z, 0-9, _ or -' };

export class CreateProductDto {
  @ApiProperty() @Matches(CODE, CODE_MSG) code: string;
  @ApiProperty() @IsString() @Length(1, 120) name: string;
  @ApiProperty() @IsString() @Length(1, 120) nameHi: string;
  @ApiProperty() @IsString() @Length(1, 120) nameMr: string;
  @ApiProperty({ enum: ProductCategory }) @IsEnum(ProductCategory) category: ProductCategory;
  @ApiProperty() @IsBoolean() isClimacteric: boolean;
  @ApiProperty() @IsBoolean() isEthyleneSensitive: boolean;
  @ApiProperty() @IsNumber() @Min(-30) @Max(40) safeTempMin: number;
  @ApiProperty() @IsNumber() @Min(-30) @Max(40) safeTempMax: number;
  @ApiProperty() @IsNumber() @Min(0) @Max(100) humidityMin: number;
  @ApiProperty() @IsNumber() @Min(0) @Max(100) humidityMax: number;
  @ApiPropertyOptional() @IsOptional() @IsNumber() @Min(0) ethyleneMaxPpm?: number;
  @ApiProperty() @IsNumber() @IsPositive() shockMaxG: number;
  @ApiProperty() @IsNumber() @IsPositive() baseShelfLifeH: number;
  @ApiProperty() @IsNumber() @IsPositive() q10: number;
  @ApiProperty() @IsNumber() @Min(0) unitPrice: number;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() active?: boolean;
}
export class UpdateProductDto extends PartialType(OmitType(CreateProductDto, ['code'] as const)) {}

export class CreateSiteDto {
  @ApiProperty() @Matches(CODE, CODE_MSG) code: string;
  @ApiProperty() @IsString() @Length(1, 160) name: string;
  @ApiProperty({ enum: SiteType }) @IsEnum(SiteType) type: SiteType;
  @ApiProperty() @IsLatitude() lat: number;
  @ApiProperty() @IsLongitude() lng: number;
  @ApiPropertyOptional() @IsOptional() @IsString() @Length(1, 300) address?: string;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() active?: boolean;
}
export class UpdateSiteDto extends PartialType(OmitType(CreateSiteDto, ['code'] as const)) {}

export class CreateStorageUnitDto {
  @ApiProperty() @IsUUID() siteId: string;
  @ApiProperty() @Matches(CODE, CODE_MSG) code: string;
  @ApiProperty({ enum: StorageUnitType }) @IsEnum(StorageUnitType) type: StorageUnitType;
  @ApiProperty() @IsNumber() @Min(-30) @Max(40) tempMin: number;
  @ApiProperty() @IsNumber() @Min(-30) @Max(40) tempMax: number;
  @ApiProperty() @IsNumber() @IsPositive() capacityKg: number;
  @ApiPropertyOptional() @IsOptional() @IsBoolean() active?: boolean;
}
export class UpdateStorageUnitDto extends PartialType(OmitType(CreateStorageUnitDto, ['siteId', 'code'] as const)) {}

export class CreateVehicleDto {
  @ApiProperty() @IsString() @Length(4, 20) regNo: string;
  @ApiProperty() @IsNumber() @IsPositive() capacityKg: number;
  @ApiProperty() @IsNumber() @Min(-30) @Max(40) reeferMinTemp: number;
  @ApiProperty() @IsNumber() @Min(-30) @Max(40) reeferMaxTemp: number;
  @ApiProperty() @IsUUID() homeSiteId: string;
  @ApiPropertyOptional({ enum: VehicleStatus }) @IsOptional() @IsEnum(VehicleStatus) status?: VehicleStatus;
}
export class UpdateVehicleDto extends PartialType(OmitType(CreateVehicleDto, ['regNo'] as const)) {}

export class CreateDeviceDto {
  @ApiProperty() @Matches(CODE, CODE_MSG) deviceCode: string;
  @ApiPropertyOptional() @IsOptional() @IsUUID() vehicleId?: string;
  @ApiPropertyOptional() @IsOptional() @IsUUID() storageUnitId?: string;
  @ApiProperty({ description: 'MQTT password; stored as bcrypt, never returned' })
  @IsString()
  @Length(16, 128)
  secret: string;
  @ApiPropertyOptional({ enum: DeviceStatus }) @IsOptional() @IsEnum(DeviceStatus) status?: DeviceStatus;
}
export class UpdateDeviceDto extends PartialType(OmitType(CreateDeviceDto, ['deviceCode'] as const)) {}
