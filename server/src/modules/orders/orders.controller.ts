import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Patch, Post, Query, UploadedFile, UseInterceptors } from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { ApiBearerAuth, ApiBody, ApiConsumes, ApiTags } from '@nestjs/swagger';
import type { AuthUser } from '../../common/auth/auth-user';
import { CurrentUser, Roles } from '../../common/auth/decorators';
import { AppError } from '../../common/errors/app-error';
import { parseCsv } from './csv';
import { ListOrdersQuery, UpdateOrderDto } from './dto/order.dto';
import { OrdersService } from './orders.service';

const MAX_CSV_BYTES = 1024 * 1024;
const MAX_CSV_ROWS = 2000;

/** CSV columns (header row, any order): external_ref, source_site_code, destination_site_code, product_code, quantity_kg, window_start, window_end. */
export function csvRowToOrder(r: Record<string, string>) {
  return {
    externalRef: r.external_ref,
    sourceSiteCode: r.source_site_code?.toUpperCase(),
    destinationSiteCode: r.destination_site_code?.toUpperCase(),
    productCode: r.product_code?.toUpperCase(),
    quantityKg: r.quantity_kg === undefined || r.quantity_kg === '' ? undefined : Number(r.quantity_kg),
    windowStart: r.window_start,
    windowEnd: r.window_end,
  };
}

@ApiTags('orders')
@ApiBearerAuth()
@Roles('MANAGER', 'ADMIN')
@Controller('orders')
export class OrdersController {
  constructor(private readonly orders: OrdersService) {}

  @Get()
  list(@Query() q: ListOrdersQuery) {
    return this.orders.list(q);
  }

  @Patch(':id')
  update(@Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateOrderDto) {
    return this.orders.update(id, dto);
  }

  @Post(':id/approve')
  @HttpCode(200)
  approve(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.orders.approve(user, id);
  }

  /** Multipart field `file`. Each row is idempotent on external_ref (origin CSV). */
  @Post('import')
  @HttpCode(200)
  @ApiConsumes('multipart/form-data')
  @ApiBody({ schema: { type: 'object', properties: { file: { type: 'string', format: 'binary' } } } })
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: MAX_CSV_BYTES, files: 1 } }))
  async import(@UploadedFile() file?: Express.Multer.File) {
    if (!file) throw new AppError('FILE_REQUIRED', 'Upload a CSV file in the "file" field');
    const rows = parseCsv(file.buffer.toString('utf8'));
    if (!rows.length) throw new AppError('EMPTY_CSV', 'The CSV has no data rows');
    if (rows.length > MAX_CSV_ROWS) throw new AppError('CSV_TOO_LARGE', `At most ${MAX_CSV_ROWS} rows per file`);
    const results = await this.orders.importMany(rows.map(csvRowToOrder), 'CSV');
    return {
      created: results.filter((r) => r.status === 'CREATED').length,
      duplicates: results.filter((r) => r.status === 'DUPLICATE').length,
      rejected: results.filter((r) => r.status === 'REJECTED').length,
      results,
    };
  }
}
