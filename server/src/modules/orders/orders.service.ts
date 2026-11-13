import { HttpStatus, Injectable } from '@nestjs/common';
import { type DispatchOrder, type OrderOrigin, Prisma } from '@prisma/client';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import type { AuthUser } from '../../common/auth/auth-user';
import { nextCode } from '../../common/codes';
import { AppError } from '../../common/errors/app-error';
import { istAt, istDay, ymd } from '../../common/ist';
import { afterCursor, toPage } from '../../common/pagination';
import { EventBus } from '../../infra/events/event-bus.service';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { allocateFefo, type Available } from '../planning/fefo';
import { TraceService } from '../trace/trace.service';
import { ExternalOrderDto, type ListOrdersQuery, type UpdateOrderDto } from './dto/order.dto';

type Tx = Prisma.TransactionClient;

/** Batch statuses that can be allocated to a new order. */
export const ALLOCATABLE = ['REGISTERED', 'GRADED', 'STORED'] as const;
/** Orders still holding their batches. */
export const ACTIVE_ORDER_STATUSES = ['DRAFT', 'APPROVED', 'PLANNED', 'IN_TRANSIT'] as const;

export interface ImportResult {
  index: number;
  externalRef: string | null;
  status: 'CREATED' | 'DUPLICATE' | 'REJECTED';
  orderId?: string;
  code?: string;
  error?: { code: string; message: string; details?: unknown };
}

const num = (v: Prisma.Decimal) => Number(v);

export function orderView(o: DispatchOrder & { batches?: { batchId: string; allocatedKg: Prisma.Decimal }[] }) {
  return {
    ...o,
    quantityKg: num(o.quantityKg),
    ...(o.batches ? { batches: o.batches.map((b) => ({ batchId: b.batchId, allocatedKg: num(b.allocatedKg) })) } : {}),
  };
}

@Injectable()
export class OrdersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly trace: TraceService,
    private readonly events: EventBus,
  ) {}

  /** Order code ORD-<yyyymmdd of the window start, IST>-<seq>. */
  newCode(tx: Tx, windowStart: Date) {
    return nextCode(tx, `ORD-${ymd(istDay(windowStart))}-`, async (prefix) =>
      (await tx.dispatchOrder.findFirst({ where: { code: { startsWith: prefix } }, orderBy: { code: 'desc' }, select: { code: true } }))?.code ?? null,
    );
  }

  // ───────────── import (ERP + CSV share this path) ─────────────

  async importMany(rows: unknown[], origin: Extract<OrderOrigin, 'ERP' | 'CSV'>): Promise<ImportResult[]> {
    const results: ImportResult[] = [];
    for (let i = 0; i < rows.length; i++) results.push(await this.importOne(rows[i], origin, i));
    return results;
  }

  private async importOne(raw: unknown, origin: 'ERP' | 'CSV', index: number): Promise<ImportResult> {
    const dto = plainToInstance(ExternalOrderDto, raw);
    const errors = await validate(dto, { whitelist: true, forbidNonWhitelisted: true });
    const ref = typeof (raw as { externalRef?: unknown })?.externalRef === 'string' ? (raw as { externalRef: string }).externalRef : null;
    const reject = (code: string, message: string, details?: unknown): ImportResult => ({ index, externalRef: ref, status: 'REJECTED', error: { code, message, details } });
    if (errors.length) return reject('VALIDATION_FAILED', 'Invalid order', errors.flatMap((e) => Object.values(e.constraints ?? {})));

    const existing = await this.prisma.dispatchOrder.findUnique({ where: { origin_externalRef: { origin, externalRef: dto.externalRef } } });
    if (existing) return { index, externalRef: dto.externalRef, status: 'DUPLICATE', orderId: existing.id, code: existing.code };

    const [source, dest, product] = await Promise.all([
      this.prisma.site.findUnique({ where: { code: dto.sourceSiteCode } }),
      this.prisma.site.findUnique({ where: { code: dto.destinationSiteCode } }),
      this.prisma.product.findUnique({ where: { code: dto.productCode } }),
    ]);
    if (!source?.active) return reject('UNKNOWN_SITE', `source site ${dto.sourceSiteCode} not found`);
    if (!dest?.active) return reject('UNKNOWN_SITE', `destination site ${dto.destinationSiteCode} not found`);
    if (!product?.active) return reject('UNKNOWN_PRODUCT', `product ${dto.productCode} not found`);
    if (source.id === dest.id) return reject('SAME_SITE', 'source and destination are the same site');
    const ws = new Date(dto.windowStart);
    const we = new Date(dto.windowEnd);
    if (we <= ws) return reject('INVALID_WINDOW', 'windowEnd must be after windowStart');

    try {
      const order = await this.prisma.$transaction(async (tx) =>
        tx.dispatchOrder.create({
          data: {
            code: await this.newCode(tx, ws),
            sourceSiteId: source.id,
            destinationSiteId: dest.id,
            productId: product.id,
            quantityKg: dto.quantityKg,
            windowStart: ws,
            windowEnd: we,
            origin,
            externalRef: dto.externalRef,
          },
        }),
      );
      await this.events.publish('order-transactions', order.id, { type: 'ORDER_IMPORTED', orderId: order.id, origin });
      return { index, externalRef: dto.externalRef, status: 'CREATED', orderId: order.id, code: order.code };
    } catch (e) {
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') {
        const raced = await this.prisma.dispatchOrder.findUnique({ where: { origin_externalRef: { origin, externalRef: dto.externalRef } } });
        if (raced) return { index, externalRef: dto.externalRef, status: 'DUPLICATE', orderId: raced.id, code: raced.code };
      }
      throw e;
    }
  }

  // ───────────── read / edit / approve ─────────────

  async list(q: ListOrdersQuery) {
    const limit = q.limit ?? 20;
    const where: Prisma.DispatchOrderWhereInput = {
      AND: [
        q.status ? { status: q.status } : {},
        q.date ? { windowStart: { gte: istAt(q.date), lt: istAt(q.date, '24:00') } } : {},
        afterCursor(q.cursor) as Prisma.DispatchOrderWhereInput,
      ],
    };
    const rows = await this.prisma.dispatchOrder.findMany({
      where,
      include: { batches: { select: { batchId: true, allocatedKg: true } } },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
    });
    const page = toPage(rows, limit);
    return { items: page.items.map(orderView), nextCursor: page.nextCursor };
  }

  async update(id: string, dto: UpdateOrderDto) {
    const order = await this.prisma.dispatchOrder.findUnique({ where: { id } });
    if (!order) throw new AppError('NOT_FOUND', 'Order not found', HttpStatus.NOT_FOUND);
    if (order.status !== 'DRAFT') throw new AppError('ORDER_NOT_EDITABLE', 'Only DRAFT orders can be edited', HttpStatus.CONFLICT);
    const ws = dto.windowStart ? new Date(dto.windowStart) : order.windowStart;
    const we = dto.windowEnd ? new Date(dto.windowEnd) : order.windowEnd;
    if (we <= ws) throw new AppError('INVALID_WINDOW', 'windowEnd must be after windowStart');
    if (dto.destinationSiteId) {
      const dest = await this.prisma.site.findUnique({ where: { id: dto.destinationSiteId } });
      if (!dest?.active) throw new AppError('UNKNOWN_SITE', 'Destination site not found');
      if (dest.id === order.sourceSiteId) throw new AppError('SAME_SITE', 'Destination equals the source site');
    }
    const updated = await this.prisma.dispatchOrder.update({
      where: { id },
      data: { quantityKg: dto.quantityKg, destinationSiteId: dto.destinationSiteId, windowStart: ws, windowEnd: we },
      include: { batches: { select: { batchId: true, allocatedKg: true } } },
    });
    return orderView(updated);
  }

  /**
   * Manager approval (W-3). Imported orders without batches get a FEFO allocation from their
   * source site now. Allocated batches become ALLOCATED and get an ALLOCATED trace event.
   */
  async approve(user: AuthUser, id: string) {
    const result = await this.prisma.$transaction(async (tx) => {
      const flipped = await tx.dispatchOrder.updateMany({ where: { id, status: 'DRAFT' }, data: { status: 'APPROVED', approvedBy: user.id } });
      if (flipped.count !== 1) {
        const exists = await tx.dispatchOrder.findUnique({ where: { id }, select: { status: true } });
        if (!exists) throw new AppError('NOT_FOUND', 'Order not found', HttpStatus.NOT_FOUND);
        throw new AppError('ORDER_NOT_DRAFT', `Order is ${exists.status}`, HttpStatus.CONFLICT);
      }
      const order = await tx.dispatchOrder.findUniqueOrThrow({ where: { id }, include: { batches: true, destinationSite: true } });
      if (!order.batches.length) {
        const avail = await this.availableAt(tx, order.sourceSiteId, order.productId);
        const need = { siteId: order.destinationSiteId, productId: order.productId, lat: order.destinationSite.lat, lng: order.destinationSite.lng, needKg: Number(order.quantityKg) };
        for (const a of allocateFefo([need], avail)) {
          await tx.orderBatch.create({ data: { orderId: id, batchId: a.batchId, allocatedKg: a.kg } });
        }
      }
      const batches = await tx.orderBatch.findMany({ where: { orderId: id } });
      for (const b of batches) {
        await tx.batch.update({ where: { id: b.batchId }, data: { status: 'ALLOCATED' } });
        await this.trace.append(tx, b.batchId, 'ALLOCATED', { orderCode: order.code, destinationSiteCode: order.destinationSite.code, allocatedKg: Number(b.allocatedKg) }, user.id);
      }
      const allocatedKg = batches.reduce((s, b) => s + Number(b.allocatedKg), 0);
      return { order: await tx.dispatchOrder.findUniqueOrThrow({ where: { id }, include: { batches: { select: { batchId: true, allocatedKg: true } } } }), allocatedKg };
    });
    await this.events.publish('order-transactions', id, { type: 'ORDER_APPROVED', orderId: id, approvedBy: user.id });
    const qty = Number(result.order.quantityKg);
    return { ...orderView(result.order), allocatedKg: result.allocatedKg, shortfallKg: Math.max(0, qty - result.allocatedKg) };
  }

  /** Batches at a site that are free to allocate, FEFO input shape. */
  async availableAt(tx: Tx, siteId: string, productId?: string): Promise<Available[]> {
    const rows = await tx.batch.findMany({
      where: {
        currentSiteId: siteId,
        ...(productId ? { productId } : {}),
        status: { in: [...ALLOCATABLE] },
        OR: [{ remainingShelfLifeH: null }, { remainingShelfLifeH: { gt: 0 } }],
        orders: { none: { order: { status: { in: [...ACTIVE_ORDER_STATUSES] } } } },
      },
      include: { currentSite: { select: { lat: true, lng: true } } },
    });
    return rows.map((b) => ({
      batchId: b.id,
      productId: b.productId,
      siteId,
      lat: b.currentSite?.lat ?? 0,
      lng: b.currentSite?.lng ?? 0,
      weightKg: Number(b.weightKg),
      shelfLifeH: b.remainingShelfLifeH === null ? null : Number(b.remainingShelfLifeH),
    }));
  }
}
