import { Body, Controller, Get, HttpCode, HttpStatus, Param, ParseUUIDPipe, Post, Req } from '@nestjs/common';
import { ApiBearerAuth, ApiHeader, ApiProperty, ApiTags } from '@nestjs/swagger';
import { SkipThrottle, Throttle } from '@nestjs/throttler';
import { plainToInstance } from 'class-transformer';
import { ArrayUnique, IsArray, IsIn, IsString, Length, validate } from 'class-validator';
import type { AppRequest } from '../../common/auth/auth-user';
import { Public, Roles } from '../../common/auth/decorators';
import { AppError } from '../../common/errors/app-error';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { ErpOrdersDto } from '../orders/dto/order.dto';
import { OrdersService } from '../orders/orders.service';
import { hashKey, newApiKey, verifySignature } from './signature';

export const SCOPES = ['orders:write'] as const;

class CreateClientDto {
  @ApiProperty() @IsString() @Length(2, 80) name: string;
  @ApiProperty({ enum: SCOPES, isArray: true }) @IsArray() @ArrayUnique() @IsIn(SCOPES, { each: true }) scopes: string[];
}

/** ERP order intake (SYN-02). No JWT: the API key + body HMAC authenticate the system. */
@ApiTags('integrations')
@Controller('integrations')
export class IntegrationsController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly orders: OrdersService,
  ) {}

  @Post('orders')
  @Public()
  @HttpCode(200)
  @Throttle({ default: { limit: 60, ttl: 60_000 } })
  @ApiHeader({ name: 'X-Api-Key', required: true })
  @ApiHeader({ name: 'X-Signature', required: true, description: 'hex HMAC-SHA256(body, api key)' })
  async receiveOrders(@Req() req: AppRequest) {
    // Authenticate before validating: an unsigned request must get 401, never a 400 that hints at the schema.
    const key = req.headers['x-api-key'];
    if (typeof key !== 'string' || !key) throw new AppError('INVALID_API_KEY', 'Missing X-Api-Key', HttpStatus.UNAUTHORIZED);
    const client = await this.prisma.integrationClient.findUnique({ where: { keyHash: hashKey(key) } });
    if (!client?.active) throw new AppError('INVALID_API_KEY', 'Unknown or disabled API key', HttpStatus.UNAUTHORIZED);
    if (!verifySignature(req.rawBody ?? '', key, req.headers['x-signature'])) {
      throw new AppError('INVALID_SIGNATURE', 'X-Signature does not match the body', HttpStatus.UNAUTHORIZED);
    }
    if (!client.scopes.includes('orders:write')) throw new AppError('FORBIDDEN_SCOPE', 'Key lacks orders:write', HttpStatus.FORBIDDEN);
    const dto = plainToInstance(ErpOrdersDto, req.body);
    const errors = await validate(dto, { whitelist: true, forbidNonWhitelisted: true });
    if (errors.length) {
      throw new AppError('VALIDATION_FAILED', 'Request validation failed', HttpStatus.BAD_REQUEST, {
        errors: errors.flatMap((e) => [...Object.values(e.constraints ?? {}), ...(e.children ?? []).map((c) => c.property)]),
      });
    }
    const results = await this.orders.importMany(dto.orders, 'ERP');
    return { client: client.name, results };
  }
}

/** ADMIN: issue/revoke ERP keys. The raw key is shown once. */
@ApiTags('admin/integrations')
@ApiBearerAuth()
@Roles('ADMIN')
@SkipThrottle()
@Controller('admin/integration-clients')
export class IntegrationClientsController {
  constructor(private readonly prisma: PrismaService) {}

  @Get()
  async list() {
    const rows = await this.prisma.integrationClient.findMany({ orderBy: { createdAt: 'desc' } });
    // Never return keyHash.
    return rows.map((r) => ({ id: r.id, name: r.name, scopes: r.scopes, active: r.active, createdAt: r.createdAt, updatedAt: r.updatedAt }));
  }

  @Post()
  async create(@Body() dto: CreateClientDto) {
    const apiKey = newApiKey();
    const row = await this.prisma.integrationClient.create({ data: { name: dto.name, scopes: dto.scopes, keyHash: hashKey(apiKey) } });
    return { id: row.id, name: row.name, scopes: row.scopes, apiKey, note: 'Store this key now; it cannot be shown again.' };
  }

  @Post(':id/disable')
  @HttpCode(200)
  async disable(@Param('id', ParseUUIDPipe) id: string) {
    const row = await this.prisma.integrationClient.update({ where: { id }, data: { active: false } });
    return { id: row.id, active: row.active };
  }
}
