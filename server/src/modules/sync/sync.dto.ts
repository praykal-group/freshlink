import { ApiProperty } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { ArrayMaxSize, ArrayMinSize, IsArray, IsDateString, IsIn, IsObject, IsUUID, ValidateNested } from 'class-validator';

export const SYNC_TYPES = [
  'BATCH_CREATE', 'BATCH_UPDATE', 'TAG_ATTACH', 'IMAGE_ATTACH', 'RECEIVE',
  'LOAD', 'TRIP_EVENT', 'GPS_POINTS', 'POD', 'ALERT_ACK', 'ROUTE_ACCEPT',
] as const;
export type SyncType = (typeof SYNC_TYPES)[number];

export class SyncOpDto {
  @ApiProperty() @IsUUID() clientOpId: string;
  @ApiProperty({ enum: SYNC_TYPES }) @IsIn(SYNC_TYPES) type: SyncType;
  @ApiProperty({ type: Object }) @IsObject() payload: Record<string, unknown>;
  @ApiProperty() @IsDateString() capturedAt: string;
}

/** The app sends its outbox in chunks of 50 (Section 10). */
export class SyncRequestDto {
  @ApiProperty({ type: [SyncOpDto] })
  @IsArray()
  @ArrayMinSize(1)
  @ArrayMaxSize(50)
  @ValidateNested({ each: true })
  @Type(() => SyncOpDto)
  ops: SyncOpDto[];
}

export type SyncStatus = 'APPLIED' | 'REJECTED' | 'UNSUPPORTED' | 'ERROR';

export interface SyncResult {
  clientOpId: string;
  type: SyncType;
  status: SyncStatus;
  /** True when this result was stored earlier and is being replayed. */
  replayed?: boolean;
  data?: unknown;
  error?: { code: string; message: string; details?: unknown };
}
