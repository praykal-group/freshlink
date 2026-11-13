import { HttpStatus } from '@nestjs/common';
import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsInt, IsOptional, IsString, Max, Min } from 'class-validator';
import { AppError } from './errors/app-error';

/** Cursor pagination `?cursor=&limit=` (default 20, max 100) → `{items, nextCursor}` (Section 6.1). */
export class PageQuery {
  @ApiPropertyOptional() @IsOptional() @IsString() cursor?: string;
  @ApiPropertyOptional({ default: 20, maximum: 100 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number;
}

export interface Page<T> {
  items: T[];
  nextCursor: string | null;
}

/** Cursor over (createdAt DESC, id DESC): opaque base64url of "<iso>|<id>". */
export function encodeCursor(createdAt: Date, id: string): string {
  return Buffer.from(`${createdAt.toISOString()}|${id}`).toString('base64url');
}

export function decodeCursor(cursor: string): { createdAt: Date; id: string } {
  const [iso, id] = Buffer.from(cursor, 'base64url').toString().split('|');
  const createdAt = new Date(iso);
  if (!id || Number.isNaN(createdAt.getTime())) throw new AppError('INVALID_CURSOR', 'Invalid cursor', HttpStatus.BAD_REQUEST);
  return { createdAt, id };
}

/** Prisma `where` fragment for rows strictly after the cursor in (createdAt desc, id desc) order. */
export function afterCursor(cursor?: string) {
  if (!cursor) return {};
  const c = decodeCursor(cursor);
  return { OR: [{ createdAt: { lt: c.createdAt } }, { createdAt: c.createdAt, id: { lt: c.id } }] };
}

/** Call with `limit + 1` rows fetched. */
export function toPage<T extends { createdAt: Date; id: string }>(rows: T[], limit: number): Page<T> {
  const items = rows.slice(0, limit);
  const last = items[items.length - 1];
  return { items, nextCursor: rows.length > limit && last ? encodeCursor(last.createdAt, last.id) : null };
}
