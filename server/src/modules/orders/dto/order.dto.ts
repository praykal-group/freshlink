import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { OrderStatus } from '@prisma/client';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  ArrayMinSize,
  IsArray,
  IsDateString,
  IsEnum,
  IsNumber,
  IsOptional,
  IsString,
  IsUUID,
  Length,
  Matches,
  Max,
  Min,
  ValidateNested,
} from 'class-validator';
import { PageQuery } from '../../../common/pagination';

const CODE = /^[A-Z0-9][A-Z0-9_-]{1,31}$/;

/** One delivery order from an ERP or a CSV row (SYN-02). Sites and products by their master codes. */
export class ExternalOrderDto {
  @ApiProperty({ description: 'Unique per source system; repeats are idempotent' })
  @IsString()
  @Length(1, 80)
  externalRef: string;

  @ApiProperty({ example: 'DCK-PTN' }) @Matches(CODE) sourceSiteCode: string;
  @ApiProperty({ example: 'DC-CSN' }) @Matches(CODE) destinationSiteCode: string;
  @ApiProperty({ example: 'ROHU' }) @Matches(CODE) productCode: string;
  @ApiProperty() @IsNumber() @Min(0.1) @Max(100_000) quantityKg: number;
  @ApiProperty() @IsDateString() windowStart: string;
  @ApiProperty() @IsDateString() windowEnd: string;
}

export class ErpOrdersDto {
  @ApiProperty({ type: [ExternalOrderDto] })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(500)
  @ValidateNested({ each: true })
  @Type(() => ExternalOrderDto)
  orders: ExternalOrderDto[];
}

export class UpdateOrderDto {
  @ApiPropertyOptional() @IsOptional() @IsNumber() @Min(0.1) @Max(100_000) quantityKg?: number;
  @ApiPropertyOptional() @IsOptional() @IsUUID() destinationSiteId?: string;
  @ApiPropertyOptional() @IsOptional() @IsDateString() windowStart?: string;
  @ApiPropertyOptional() @IsOptional() @IsDateString() windowEnd?: string;
}

export class ListOrdersQuery extends PageQuery {
  @ApiPropertyOptional({ enum: OrderStatus }) @IsOptional() @IsEnum(OrderStatus) status?: OrderStatus;
  @ApiPropertyOptional({ description: 'IST day of windowStart, YYYY-MM-DD' })
  @IsOptional()
  @Matches(/^\d{4}-\d{2}-\d{2}$/)
  date?: string;
}
