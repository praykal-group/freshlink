import { HttpStatus, Injectable } from '@nestjs/common';
import { type BackupBuyer, Prisma } from '@prisma/client';
import { AppError } from '../../common/errors/app-error';
import { afterCursor, toPage } from '../../common/pagination';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { type BuyerIn, type OpeningHours, openingHoursSchema } from './buyer-rules';
import type { CreateBuyerDto, ListBuyersQuery, UpdateBuyerDto } from './dto/buyer.dto';

export const buyerView = (b: BackupBuyer) => ({ ...b, discountPct: Number(b.discountPct), capacityKg: b.capacityKg === null ? null : Number(b.capacityKg) });

export const toBuyerIn = (b: BackupBuyer): BuyerIn => ({
  id: b.id,
  name: b.name,
  type: b.type,
  lat: b.lat,
  lng: b.lng,
  acceptedProductIds: b.acceptedProductIds,
  minGrade: b.minGrade,
  discountPct: Number(b.discountPct),
  openingHours: b.openingHours as OpeningHours,
  capacityKg: b.capacityKg === null ? null : Number(b.capacityKg),
  active: b.active,
});

/** Backup buyer registry (W-1). Delete = `active=false` so offers and stops keep their buyer. */
@Injectable()
export class BuyersService {
  constructor(private readonly prisma: PrismaService) {}

  async list(q: ListBuyersQuery) {
    const limit = q.limit ?? 20;
    const rows = await this.prisma.backupBuyer.findMany({
      where: {
        AND: [
          q.type ? { type: q.type } : {},
          q.active !== undefined ? { active: q.active } : {},
          q.productId ? { acceptedProductIds: { has: q.productId } } : {},
          afterCursor(q.cursor) as Prisma.BackupBuyerWhereInput,
        ],
      },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
    });
    const page = toPage(rows, limit);
    return { items: page.items.map(buyerView), nextCursor: page.nextCursor };
  }

  async get(id: string) {
    const b = await this.prisma.backupBuyer.findUnique({ where: { id } });
    if (!b) throw new AppError('NOT_FOUND', 'Buyer not found', HttpStatus.NOT_FOUND);
    return buyerView(b);
  }

  async create(dto: CreateBuyerDto) {
    await this.check(dto);
    const b = await this.prisma.backupBuyer.create({
      data: { ...dto, openingHours: dto.openingHours as Prisma.InputJsonValue, active: dto.active ?? true },
    });
    return buyerView(b);
  }

  async update(id: string, dto: UpdateBuyerDto) {
    await this.get(id);
    await this.check(dto);
    const b = await this.prisma.backupBuyer.update({
      where: { id },
      data: { ...dto, ...(dto.openingHours ? { openingHours: dto.openingHours as Prisma.InputJsonValue } : {}) },
    });
    return buyerView(b);
  }

  async deactivate(id: string) {
    await this.get(id);
    return buyerView(await this.prisma.backupBuyer.update({ where: { id }, data: { active: false } }));
  }

  private async check(dto: Partial<CreateBuyerDto>) {
    if (dto.openingHours !== undefined) {
      const parsed = openingHoursSchema.safeParse(dto.openingHours);
      if (!parsed.success) {
        throw new AppError('VALIDATION_FAILED', 'openingHours must be {"mon":[["HH:MM","HH:MM"]], ...} with weekday keys sun..sat', HttpStatus.UNPROCESSABLE_ENTITY, {
          issues: parsed.error.issues.map((i) => ({ path: i.path.join('.'), message: i.message })),
        });
      }
    }
    if (dto.acceptedProductIds?.length) {
      const found = await this.prisma.product.count({ where: { id: { in: dto.acceptedProductIds } } });
      if (found !== new Set(dto.acceptedProductIds).size) throw new AppError('UNKNOWN_PRODUCT', 'Some accepted products do not exist', HttpStatus.UNPROCESSABLE_ENTITY);
    }
  }
}
