import { HttpStatus, Injectable } from '@nestjs/common';
import type { Grade, Prisma, Product, StorageUnit } from '@prisma/client';
import { AppError } from '../../common/errors/app-error';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { decideStoragePath, freeKg, type ProductLike, rankUnits, tempFits, type UnitLike } from './storage-rules';

type Tx = Prisma.TransactionClient;

export const toProductLike = (p: Product): ProductLike => ({
  category: p.category,
  isClimacteric: p.isClimacteric,
  safeTempMin: Number(p.safeTempMin),
  safeTempMax: Number(p.safeTempMax),
});

export const toUnitLike = (u: StorageUnit): UnitLike => ({
  id: u.id,
  code: u.code,
  type: u.type,
  tempMin: Number(u.tempMin),
  tempMax: Number(u.tempMax),
  capacityKg: Number(u.capacityKg),
  usedKg: Number(u.usedKg),
  active: u.active,
});

const unitView = (u: UnitLike) => ({
  id: u.id,
  code: u.code,
  type: u.type,
  tempMin: u.tempMin,
  tempMax: u.tempMax,
  freeKg: Math.round(freeKg(u) * 1000) / 1000,
});

/** Storage path gate + unit recommendation (SYN-10, SYN-20) and capacity bookkeeping. */
@Injectable()
export class StorageService {
  constructor(private readonly prisma: PrismaService) {}

  async recommend(input: { product: Product; grade: Grade | null; siteId: string | null; weightKg: number }) {
    const product = toProductLike(input.product);
    const decision = decideStoragePath(product, input.grade);
    const units = input.siteId ? (await this.prisma.storageUnit.findMany({ where: { siteId: input.siteId } })).map(toUnitLike) : [];
    const ranked = rankUnits(units, product, decision.path, input.weightKg);
    return {
      ...decision,
      recommendedUnit: ranked[0] ? unitView(ranked[0]) : null,
      alternatives: ranked.slice(1, 4).map(unitView),
      note: ranked.length ? undefined : `No ${decision.path} with ${input.weightKg} kg free and a fitting temperature at this site`,
    };
  }

  /**
   * Moves a batch into a unit inside the caller's transaction. Capacity is reserved with a single
   * conditional UPDATE, so two operators cannot over-fill the same unit concurrently.
   */
  async assign(tx: Tx, args: { unitId: string; siteId: string | null; product: Product; weightKg: number; previousUnitId: string | null }) {
    const unit = await tx.storageUnit.findUnique({ where: { id: args.unitId } });
    if (!unit || !unit.active) throw new AppError('NOT_FOUND', 'Storage unit not found', HttpStatus.NOT_FOUND);
    if (unit.siteId !== args.siteId) {
      throw new AppError('UNIT_AT_OTHER_SITE', 'Storage unit is at another site', HttpStatus.CONFLICT);
    }
    if (!tempFits(toUnitLike(unit), toProductLike(args.product))) {
      throw new AppError('UNIT_TEMP_MISMATCH', "Unit temperature range does not fit this product's safe range", HttpStatus.CONFLICT);
    }
    if (args.previousUnitId === unit.id) return unit;

    if (args.previousUnitId) await this.release(tx, args.previousUnitId, args.weightKg);
    await this.reserve(tx, unit.id, args.weightKg, unit.code);
    return unit;
  }

  /** Atomic "add kg if it fits". Throws UNIT_FULL when it does not. */
  async reserve(tx: Tx, unitId: string, weightKg: number, unitCode = 'unit') {
    const reserved = await tx.$executeRaw`
      UPDATE storage_units SET used_kg = used_kg + ${weightKg}::numeric, updated_at = now()
      WHERE id = ${unitId}::uuid AND used_kg + ${weightKg}::numeric <= capacity_kg`;
    if (reserved !== 1) {
      throw new AppError('UNIT_FULL', `${unitCode} does not have ${weightKg} kg free`, HttpStatus.CONFLICT);
    }
  }

  /** Weight correction of a stored batch: release the old weight, reserve the new one. */
  async resize(tx: Tx, unitId: string, oldKg: number, newKg: number) {
    await this.release(tx, unitId, oldKg);
    await this.reserve(tx, unitId, newKg);
  }

  async release(tx: Tx, unitId: string, weightKg: number) {
    await tx.$executeRaw`
      UPDATE storage_units SET used_kg = GREATEST(used_kg - ${weightKg}::numeric, 0), updated_at = now()
      WHERE id = ${unitId}::uuid`;
  }
}
