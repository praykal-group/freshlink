import { ApiProperty, ApiPropertyOptional, PartialType } from '@nestjs/swagger';
import { BuyerType, Grade } from '@prisma/client';
import { Transform } from 'class-transformer';
import {
  ArrayMaxSize, ArrayMinSize, IsArray, IsBoolean, IsEmail, IsEnum, IsLatitude, IsLongitude, IsNumber, IsObject, IsOptional, IsString, IsUUID, Length, Matches, Max, Min,
} from 'class-validator';
import { PageQuery } from '../../../common/pagination';

export class CreateBuyerDto {
  @ApiProperty() @IsString() @Length(2, 120) name: string;
  @ApiProperty({ enum: BuyerType }) @IsEnum(BuyerType) type: BuyerType;
  @ApiProperty({ example: '+919999900101' }) @Matches(/^\+[1-9]\d{7,14}$/, { message: 'phone must be E.164' }) phone: string;
  @ApiPropertyOptional() @IsOptional() @IsEmail() email?: string;
  @ApiProperty() @IsLatitude() lat: number;
  @ApiProperty() @IsLongitude() lng: number;
  @ApiProperty({ type: [String] }) @IsArray() @ArrayMinSize(1) @ArrayMaxSize(100) @IsUUID('4', { each: true }) acceptedProductIds: string[];
  @ApiProperty({ enum: Grade }) @IsEnum(Grade) minGrade: Grade;
  @ApiProperty() @IsNumber() @Min(0) @Max(100) discountPct: number;
  @ApiProperty({ example: { mon: [['06:00', '20:00']] } }) @IsObject() openingHours: Record<string, [string, string][]>;
  @ApiPropertyOptional() @IsOptional() @IsNumber() @Min(1) capacityKg?: number;
  @ApiPropertyOptional({ default: true }) @IsOptional() @IsBoolean() active?: boolean;
}

export class UpdateBuyerDto extends PartialType(CreateBuyerDto) {}

export class ListBuyersQuery extends PageQuery {
  @ApiPropertyOptional({ enum: BuyerType }) @IsOptional() @IsEnum(BuyerType) type?: BuyerType;
  @ApiPropertyOptional()
  @IsOptional()
  @Transform(({ value }) => (value === 'true' ? true : value === 'false' ? false : value))
  @IsBoolean()
  active?: boolean;
  @ApiPropertyOptional() @IsOptional() @IsUUID() productId?: string;
}
