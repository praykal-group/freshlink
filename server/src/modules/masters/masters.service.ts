import { HttpStatus, Injectable } from '@nestjs/common';
import type { IotDevice } from '@prisma/client';
import { hash } from 'bcryptjs';
import { createHash } from 'node:crypto';
import { AppError } from '../../common/errors/app-error';
import { PrismaService } from '../../infra/prisma/prisma.service';
import type {
  CreateDeviceDto,
  CreateProductDto,
  CreateSiteDto,
  CreateStorageUnitDto,
  CreateVehicleDto,
  UpdateDeviceDto,
  UpdateProductDto,
  UpdateSiteDto,
  UpdateStorageUnitDto,
  UpdateVehicleDto,
} from './dto/masters.dto';

const BCRYPT_ROUNDS = 10;

function assertRange(min: unknown, max: unknown, field: string) {
  if (typeof min === 'number' && typeof max === 'number' && min > max) {
    throw new AppError('INVALID_RANGE', `${field}: min must not exceed max`, HttpStatus.BAD_REQUEST);
  }
}

function notFound(entity: string): never {
  throw new AppError('NOT_FOUND', `${entity} not found`, HttpStatus.NOT_FOUND);
}

/** Device rows never leave the server with their secret hash. */
function publicDevice(d: IotDevice) {
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  const { secretHash, ...rest } = d;
  return rest;
}

@Injectable()
export class MastersService {
  constructor(private readonly prisma: PrismaService) {}

  // ── products ──
  listProducts() {
    return this.prisma.product.findMany({ orderBy: { code: 'asc' } });
  }
  createProduct(dto: CreateProductDto) {
    assertRange(dto.safeTempMin, dto.safeTempMax, 'safeTemp');
    assertRange(dto.humidityMin, dto.humidityMax, 'humidity');
    return this.prisma.product.create({ data: dto });
  }
  async updateProduct(id: string, dto: UpdateProductDto) {
    const cur = (await this.prisma.product.findUnique({ where: { id } })) ?? notFound('Product');
    assertRange(dto.safeTempMin ?? Number(cur.safeTempMin), dto.safeTempMax ?? Number(cur.safeTempMax), 'safeTemp');
    assertRange(dto.humidityMin ?? Number(cur.humidityMin), dto.humidityMax ?? Number(cur.humidityMax), 'humidity');
    return this.prisma.product.update({ where: { id }, data: dto });
  }

  // ── sites ──
  listSites() {
    return this.prisma.site.findMany({ orderBy: { code: 'asc' } });
  }
  createSite(dto: CreateSiteDto) {
    return this.prisma.site.create({ data: dto });
  }
  async updateSite(id: string, dto: UpdateSiteDto) {
    if (!(await this.prisma.site.findUnique({ where: { id }, select: { id: true } }))) notFound('Site');
    return this.prisma.site.update({ where: { id }, data: dto });
  }

  // ── storage units ──
  listStorageUnits(siteId?: string) {
    return this.prisma.storageUnit.findMany({ where: siteId ? { siteId } : undefined, orderBy: [{ siteId: 'asc' }, { code: 'asc' }] });
  }
  createStorageUnit(dto: CreateStorageUnitDto) {
    assertRange(dto.tempMin, dto.tempMax, 'temp');
    return this.prisma.storageUnit.create({ data: dto });
  }
  async updateStorageUnit(id: string, dto: UpdateStorageUnitDto) {
    const cur = (await this.prisma.storageUnit.findUnique({ where: { id } })) ?? notFound('Storage unit');
    assertRange(dto.tempMin ?? Number(cur.tempMin), dto.tempMax ?? Number(cur.tempMax), 'temp');
    if (dto.capacityKg !== undefined && dto.capacityKg < Number(cur.usedKg)) {
      throw new AppError('CAPACITY_BELOW_USED', 'capacityKg cannot be below the kg already stored', HttpStatus.CONFLICT);
    }
    return this.prisma.storageUnit.update({ where: { id }, data: dto });
  }

  // ── vehicles ──
  listVehicles() {
    return this.prisma.vehicle.findMany({ orderBy: { regNo: 'asc' } });
  }
  createVehicle(dto: CreateVehicleDto) {
    assertRange(dto.reeferMinTemp, dto.reeferMaxTemp, 'reeferTemp');
    return this.prisma.vehicle.create({ data: { ...dto, regNo: dto.regNo.toUpperCase() } });
  }
  async updateVehicle(id: string, dto: UpdateVehicleDto) {
    const cur = (await this.prisma.vehicle.findUnique({ where: { id } })) ?? notFound('Vehicle');
    assertRange(dto.reeferMinTemp ?? Number(cur.reeferMinTemp), dto.reeferMaxTemp ?? Number(cur.reeferMaxTemp), 'reeferTemp');
    return this.prisma.vehicle.update({ where: { id }, data: dto });
  }

  // ── IoT devices (secret → bcrypt, Section 14) ──
  async listDevices() {
    return (await this.prisma.iotDevice.findMany({ orderBy: { deviceCode: 'asc' } })).map(publicDevice);
  }
  async createDevice(dto: CreateDeviceDto) {
    const { secret, ...rest } = dto;
    const row = await this.prisma.iotDevice.create({
      data: { ...rest, mqttUsername: dto.deviceCode.toLowerCase(), secretHash: await hash(secret, BCRYPT_ROUNDS) },
    });
    return publicDevice(row);
  }
  async updateDevice(id: string, dto: UpdateDeviceDto) {
    if (!(await this.prisma.iotDevice.findUnique({ where: { id }, select: { id: true } }))) notFound('Device');
    const { secret, ...rest } = dto;
    const row = await this.prisma.iotDevice.update({
      where: { id },
      data: { ...rest, ...(secret ? { secretHash: await hash(secret, BCRYPT_ROUNDS) } : {}) },
    });
    return publicDevice(row);
  }

  // ── offline bundle ──

  /**
   * Cheap fingerprint of everything the bundle contains: row counts + newest updated_at per table.
   * Any create/update/(de)activation changes it, so it is a valid strong ETag.
   */
  async bundleEtag(since?: Date): Promise<string> {
    const [p, s, u, c] = await Promise.all([
      this.prisma.product.aggregate({ _count: true, _max: { updatedAt: true } }),
      this.prisma.site.aggregate({ _count: true, _max: { updatedAt: true } }),
      this.prisma.storageUnit.aggregate({ _count: true, _max: { updatedAt: true } }),
      this.prisma.appConfig.aggregate({ _count: true, _max: { updatedAt: true } }),
    ]);
    const parts = [p, s, u, c].map((a) => `${a._count}:${a._max.updatedAt?.toISOString() ?? '-'}`);
    parts.push(since?.toISOString() ?? 'all');
    return `"${createHash('sha256').update(parts.join('|')).digest('base64url').slice(0, 27)}"`;
  }

  /** Without `since`: active rows only. With `since`: every row changed after it, incl. deactivated ones. */
  async bundle(since?: Date) {
    const changed = since ? { updatedAt: { gt: since } } : { active: true };
    const [products, sites, storageUnits, config] = await Promise.all([
      this.prisma.product.findMany({ where: changed, orderBy: { code: 'asc' } }),
      this.prisma.site.findMany({ where: changed, orderBy: { code: 'asc' } }),
      this.prisma.storageUnit.findMany({ where: changed, orderBy: [{ siteId: 'asc' }, { code: 'asc' }] }),
      this.prisma.appConfig.findMany({ where: since ? { updatedAt: { gt: since } } : undefined }),
    ]);
    return {
      generatedAt: new Date().toISOString(),
      since: since?.toISOString() ?? null,
      products,
      sites,
      storageUnits,
      config: Object.fromEntries(config.map((c) => [c.key, c.value])),
    };
  }
}
