import { HttpStatus, Injectable } from '@nestjs/common';
import { type Batch, type BatchStatus, Prisma } from '@prisma/client';
import type { AuthUser } from '../../common/auth/auth-user';
import { Ownership } from '../../common/auth/ownership';
import { AppError } from '../../common/errors/app-error';
import { recordHash } from '../../common/hashing/hashing';
import { afterCursor, toPage } from '../../common/pagination';
import { EventBus } from '../../infra/events/event-bus.service';
import { PrismaService } from '../../infra/prisma/prisma.service';
import { FilesService } from '../files/files.service';
import { RemoteConfigService } from '../remote-config/remote-config.service';
import { StorageService } from '../storage/storage.service';
import { TraceService } from '../trace/trace.service';
import { batchCode, batchCodePrefix, categoryProblems, withinEditWindow } from './batch-rules';
import {
  type AttachImageDto,
  type AttachTagDto,
  type CreateBatchDto,
  EDITABLE_FIELDS,
  type EditableBatchFieldsDto,
  type EditRequestDto,
  type ListBatchesQuery,
  type ListEditRequestsQuery,
  type ReceiveDto,
} from './dto/batch.dto';

type Tx = Prisma.TransactionClient;
type EditableField = (typeof EDITABLE_FIELDS)[number];

/** Statuses in which a batch is physically at a site and can be stored/moved between units. */
const AT_SITE: BatchStatus[] = ['REGISTERED', 'GRADED', 'STORED'];
const DATE_FIELDS: EditableField[] = ['caughtOrHarvestedAt'];

const num = (v: Prisma.Decimal | null | undefined) => (v === null || v === undefined ? null : Number(v));

function fail(code: string, message: string, status: HttpStatus, details?: Record<string, unknown>): never {
  throw new AppError(code, message, status, details);
}

/** Public JSON shape of a batch (Decimals → numbers). */
export function batchView(b: Batch) {
  return {
    id: b.id,
    code: b.code,
    productId: b.productId,
    sourceType: b.sourceType,
    sourceSiteId: b.sourceSiteId,
    currentSiteId: b.currentSiteId,
    storageUnitId: b.storageUnitId,
    vesselId: b.vesselId,
    farmRef: b.farmRef,
    caughtOrHarvestedAt: b.caughtOrHarvestedAt,
    weightKg: num(b.weightKg),
    iceToFishRatio: num(b.iceToFishRatio),
    initialCoreTemp: num(b.initialCoreTemp),
    maturityIndex: num(b.maturityIndex),
    brix: num(b.brix),
    fieldTemp: num(b.fieldTemp),
    fieldHumidity: num(b.fieldHumidity),
    status: b.status,
    currentGrade: b.currentGrade,
    remainingShelfLifeH: num(b.remainingShelfLifeH),
    shelfLifeUpdatedAt: b.shelfLifeUpdatedAt,
    createdBy: b.createdBy,
    deviceId: b.deviceId,
    capturedAt: b.capturedAt,
    capturedLat: b.capturedLat,
    capturedLng: b.capturedLng,
    recordHash: b.recordHash,
    createdAt: b.createdAt,
    updatedAt: b.updatedAt,
  };
}

@Injectable()
export class BatchesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly trace: TraceService,
    private readonly files: FilesService,
    private readonly storage: StorageService,
    private readonly config: RemoteConfigService,
    private readonly events: EventBus,
  ) {}

  // ───────────────────────── create (idempotent on client UUID) ─────────────────────────

  async create(user: AuthUser, dto: CreateBatchDto, deviceId: string | undefined) {
    const existing = await this.prisma.batch.findUnique({ where: { id: dto.id } });
    if (existing) return this.idempotentReplay(user, existing);

    const siteId = this.resolveCreateSite(user, dto.siteId);
    if (!deviceId) fail('MISSING_DEVICE_ID', 'X-Device-Id header is required to register a batch', HttpStatus.BAD_REQUEST);

    const [product, site] = await Promise.all([
      this.prisma.product.findUnique({ where: { id: dto.productId } }),
      this.prisma.site.findUnique({ where: { id: siteId } }),
    ]);
    if (!product || !product.active) fail('UNKNOWN_PRODUCT', 'Product not found or inactive', HttpStatus.BAD_REQUEST);
    if (!site || !site.active) fail('UNKNOWN_SITE', 'Site not found or inactive', HttpStatus.BAD_REQUEST);

    const problems = categoryProblems(product.category, dto);
    if (problems.length) fail('VALIDATION_FAILED', 'Batch fields do not match the product category', HttpStatus.BAD_REQUEST, { problems });

    const capturedAt = new Date(dto.capturedAt);
    const prefix = batchCodePrefix(product.category, site.code, capturedAt);
    const hash = recordHash({ ...dto, siteId, createdBy: user.id, deviceId });

    try {
      const batch = await this.prisma.$transaction(async (tx) => {
        // Serialise code allocation per prefix (site + day) so sequences never collide.
        await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${prefix}))`;
        const last = await tx.batch.findFirst({ where: { code: { startsWith: prefix } }, orderBy: { code: 'desc' }, select: { code: true } });
        const seq = last ? Number(last.code.slice(prefix.length)) + 1 : 1;
        const created = await tx.batch.create({
          data: {
            id: dto.id,
            code: batchCode(prefix, seq),
            productId: product.id,
            sourceType: product.category === 'FISH' ? 'FISHERY' : 'FARM',
            sourceSiteId: site.id,
            currentSiteId: site.id,
            vesselId: dto.vesselId,
            farmRef: dto.farmRef,
            caughtOrHarvestedAt: new Date(dto.caughtOrHarvestedAt),
            weightKg: dto.weightKg,
            iceToFishRatio: dto.iceToFishRatio,
            initialCoreTemp: dto.initialCoreTemp,
            maturityIndex: dto.maturityIndex,
            brix: dto.brix,
            fieldTemp: dto.fieldTemp,
            fieldHumidity: dto.fieldHumidity,
            createdBy: user.id,
            deviceId,
            capturedAt,
            capturedLat: dto.capturedLat,
            capturedLng: dto.capturedLng,
            recordHash: hash,
          },
        });
        await this.trace.append(
          tx,
          created.id,
          'REGISTERED',
          {
            code: created.code,
            productCode: product.code,
            sourceType: created.sourceType,
            siteCode: site.code,
            weightKg: dto.weightKg,
            caughtOrHarvestedAt: created.caughtOrHarvestedAt.toISOString(),
            recordHash: hash,
          },
          user.id,
          capturedAt,
        );
        return created;
      });
      return batchView(batch);
    } catch (e) {
      // Two identical offline retries racing each other: the loser replays the winner's row.
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') {
        const raced = await this.prisma.batch.findUnique({ where: { id: dto.id } });
        if (raced) return this.idempotentReplay(user, raced);
      }
      throw e;
    }
  }

  private idempotentReplay(user: AuthUser, existing: Batch) {
    if (existing.createdBy !== user.id) fail('DUPLICATE', 'A batch with this id already exists', HttpStatus.CONFLICT);
    return batchView(existing);
  }

  private resolveCreateSite(user: AuthUser, requested?: string): string {
    if (user.role === 'OPERATOR') {
      if (!user.siteId) fail('NO_SITE', 'Operator is not linked to a site', HttpStatus.FORBIDDEN);
      if (requested && requested !== user.siteId) fail('FORBIDDEN_SITE', 'Operators register batches at their own site', HttpStatus.FORBIDDEN);
      return user.siteId;
    }
    if (!requested) fail('SITE_REQUIRED', 'siteId is required', HttpStatus.BAD_REQUEST);
    return requested;
  }

  // ───────────────────────── read ─────────────────────────

  async list(user: AuthUser, q: ListBatchesQuery) {
    const limit = q.limit ?? 20;
    const siteId = user.role === 'OPERATOR' ? user.siteId : q.siteId;
    if (user.role === 'OPERATOR' && q.siteId && q.siteId !== user.siteId) {
      fail('FORBIDDEN_SITE', 'Operators only see their own site', HttpStatus.FORBIDDEN);
    }
    const term = q.q?.trim();
    const where: Prisma.BatchWhereInput = {
      AND: [
        siteId ? { OR: [{ currentSiteId: siteId }, { sourceSiteId: siteId }] } : {},
        q.status ? { status: q.status } : {},
        term ? { OR: [{ code: { contains: term.toUpperCase() } }, { tags: { some: { tagUid: term } } }] } : {},
        afterCursor(q.cursor),
      ],
    };
    const rows = await this.prisma.batch.findMany({ where, orderBy: [{ createdAt: 'desc' }, { id: 'desc' }], take: limit + 1 });
    const page = toPage(rows, limit);
    return { items: page.items.map(batchView), nextCursor: page.nextCursor };
  }

  async get(user: AuthUser, id: string) {
    const batch = await this.loadForUser(user, id);
    const detail = await this.prisma.batch.findUniqueOrThrow({
      where: { id },
      include: {
        product: { select: { id: true, code: true, name: true, nameHi: true, nameMr: true, category: true, isClimacteric: true } },
        tags: { select: { tagType: true, tagUid: true, createdAt: true } },
        images: { select: { view: true, s3Key: true, capturedAt: true } },
        storageUnit: { select: { id: true, code: true, type: true } },
      },
    });
    return { ...batchView(batch), product: detail.product, tags: detail.tags, images: detail.images, storageUnit: detail.storageUnit };
  }

  /** Loads a batch and applies the site ownership rule (operators: own site only). */
  async loadForUser(user: AuthUser, id: string): Promise<Batch> {
    const batch = await this.prisma.batch.findUnique({ where: { id } });
    if (!batch) fail('NOT_FOUND', 'Batch not found', HttpStatus.NOT_FOUND);
    if (user.role === 'OPERATOR' && batch.currentSiteId !== user.siteId && batch.sourceSiteId !== user.siteId) {
      fail('FORBIDDEN_SITE', 'Batch belongs to another site', HttpStatus.FORBIDDEN);
    }
    if (user.role === 'DRIVER') fail('FORBIDDEN_ROLE', 'Drivers cannot access batches directly', HttpStatus.FORBIDDEN);
    return batch;
  }

  // ───────────────────────── edits (FO-FR-13) ─────────────────────────

  /**
   * Direct correction inside the edit window, by an operator of the batch's site.
   * Online: server clock vs created_at. Offline (via /sync, `editedAt` = op capturedAt): device clock
   * vs the batch's device capture time, so an edit made offline within 30 min still counts. The
   * device time may not be in the future; the audit log keeps both times.
   */
  async update(user: AuthUser, id: string, dto: EditableBatchFieldsDto, editedAt?: Date) {
    const batch = await this.loadForUser(user, id);
    Ownership.assertSite(user, batch.currentSiteId);
    const windowMin = await this.config.get('editWindowMin');
    const now = new Date();
    const offline = editedAt && editedAt.getTime() <= now.getTime() + 2 * 60_000;
    const inWindow = offline ? withinEditWindow(batch.capturedAt, editedAt, windowMin) : withinEditWindow(batch.createdAt, now, windowMin);
    if (!inWindow) {
      fail('EDIT_WINDOW_CLOSED', `Direct edits are allowed for ${windowMin} min after creation; send an edit request`, HttpStatus.CONFLICT, {
        windowMin,
        createdAt: batch.createdAt,
      });
    }
    const updated = await this.prisma.$transaction((tx) => this.applyChanges(tx, user, batch, dto, { via: 'DIRECT' }));
    return batchView(updated);
  }

  async createEditRequest(user: AuthUser, id: string, dto: EditRequestDto) {
    const batch = await this.loadForUser(user, id);
    Ownership.assertSite(user, batch.currentSiteId);
    const changes = this.diff(batch, dto.changes);
    if (!Object.keys(changes).length) fail('NO_CHANGES', 'The request does not change anything', HttpStatus.BAD_REQUEST);
    const pending = await this.prisma.batchEditRequest.count({ where: { batchId: id, status: 'PENDING' } });
    if (pending) fail('EDIT_REQUEST_PENDING', 'This batch already has a pending edit request', HttpStatus.CONFLICT);
    return this.prisma.batchEditRequest.create({
      data: { batchId: id, requestedBy: user.id, changes: dto.changes as Prisma.InputJsonValue, reason: dto.reason },
    });
  }

  async listEditRequests(q: ListEditRequestsQuery) {
    const limit = q.limit ?? 20;
    const rows = await this.prisma.batchEditRequest.findMany({
      where: { AND: [q.status ? { status: q.status } : {}, afterCursor(q.cursor)] },
      include: { batch: { select: { code: true } }, requester: { select: { name: true } } },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      take: limit + 1,
    });
    return toPage(rows, limit);
  }

  async reviewEditRequest(user: AuthUser, requestId: string, approve: boolean, note?: string) {
    return this.prisma.$transaction(async (tx) => {
      const req = await tx.batchEditRequest.findUnique({ where: { id: requestId } });
      if (!req) fail('NOT_FOUND', 'Edit request not found', HttpStatus.NOT_FOUND);
      // Conditional status flip: a second reviewer racing this one gets ALREADY_REVIEWED.
      const flipped = await tx.batchEditRequest.updateMany({
        where: { id: requestId, status: 'PENDING' },
        data: { status: approve ? 'APPROVED' : 'REJECTED', reviewedBy: user.id, reviewedAt: new Date() },
      });
      if (flipped.count !== 1) fail('ALREADY_REVIEWED', 'This request was already reviewed', HttpStatus.CONFLICT);
      if (approve) {
        const batch = await tx.batch.findUniqueOrThrow({ where: { id: req.batchId } });
        await this.applyChanges(tx, user, batch, req.changes as EditableBatchFieldsDto, { via: 'EDIT_REQUEST', requestId, note });
      }
      return tx.batchEditRequest.findUniqueOrThrow({ where: { id: requestId } });
    });
  }

  /** Field-level diff; values normalised so "no real change" is detected. */
  private diff(batch: Batch, dto: EditableBatchFieldsDto): Record<string, { from: unknown; to: unknown }> {
    const out: Record<string, { from: unknown; to: unknown }> = {};
    for (const f of EDITABLE_FIELDS) {
      const to = dto[f];
      if (to === undefined) continue;
      const current = batch[f] as unknown;
      const from =
        current instanceof Date ? current.toISOString() : current instanceof Prisma.Decimal ? Number(current) : (current ?? null);
      const next = DATE_FIELDS.includes(f) ? new Date(to as string).toISOString() : to;
      if (from !== next) out[f] = { from, to: next };
    }
    return out;
  }

  /**
   * Applies corrections. Original values are never overwritten silently: every change is in
   * audit_logs (before/after) and in the trace chain as BATCH_CORRECTED.
   */
  private async applyChanges(
    tx: Tx,
    user: AuthUser,
    batch: Batch,
    dto: EditableBatchFieldsDto,
    meta: { via: 'DIRECT' | 'EDIT_REQUEST'; requestId?: string; note?: string },
  ): Promise<Batch> {
    const changes = this.diff(batch, dto);
    if (!Object.keys(changes).length) return batch;

    const product = await tx.product.findUniqueOrThrow({ where: { id: batch.productId } });
    const merged = { ...batchView(batch), ...Object.fromEntries(Object.entries(changes).map(([k, v]) => [k, v.to])) };
    const problems = categoryProblems(product.category, {
      vesselId: merged.vesselId ?? undefined,
      farmRef: merged.farmRef ?? undefined,
      iceToFishRatio: merged.iceToFishRatio ?? undefined,
      initialCoreTemp: merged.initialCoreTemp ?? undefined,
      maturityIndex: merged.maturityIndex ?? undefined,
      brix: merged.brix ?? undefined,
      fieldTemp: merged.fieldTemp ?? undefined,
      fieldHumidity: merged.fieldHumidity ?? undefined,
    });
    if (problems.length) fail('VALIDATION_FAILED', 'Corrected values are not valid for this product', HttpStatus.BAD_REQUEST, { problems });

    if (changes.weightKg && batch.storageUnitId) {
      await this.storage.resize(tx, batch.storageUnitId, Number(batch.weightKg), changes.weightKg.to as number);
    }
    const data: Prisma.BatchUpdateInput = {};
    for (const [f, v] of Object.entries(changes)) {
      (data as Record<string, unknown>)[f] = DATE_FIELDS.includes(f as EditableField) ? new Date(v.to as string) : v.to;
    }
    const updated = await tx.batch.update({ where: { id: batch.id }, data });
    await this.trace.append(tx, batch.id, 'BATCH_CORRECTED', { changes, via: meta.via, requestId: meta.requestId ?? null }, user.id);
    await tx.auditLog.create({
      data: {
        actorId: user.id,
        action: meta.via === 'DIRECT' ? 'BATCH_EDIT' : 'BATCH_EDIT_APPROVED',
        entity: 'batches',
        entityId: batch.id,
        before: Object.fromEntries(Object.entries(changes).map(([k, v]) => [k, v.from])) as Prisma.InputJsonValue,
        after: Object.fromEntries(Object.entries(changes).map(([k, v]) => [k, v.to])) as Prisma.InputJsonValue,
      },
    });
    return updated;
  }

  // ───────────────────────── tags and images ─────────────────────────

  async attachTag(user: AuthUser, id: string, dto: AttachTagDto) {
    const batch = await this.loadForUser(user, id);
    Ownership.assertSite(user, batch.currentSiteId);
    const existing = await this.prisma.batchTag.findUnique({ where: { tagUid: dto.tagUid } });
    if (existing) {
      if (existing.batchId === id) return existing; // idempotent re-tap
      fail('TAG_IN_USE', 'This tag is already attached to another batch', HttpStatus.CONFLICT);
    }
    return this.prisma.$transaction(async (tx) => {
      const tag = await tx.batchTag.create({ data: { batchId: id, tagType: dto.tagType, tagUid: dto.tagUid, attachedBy: user.id } });
      await this.trace.append(tx, id, 'TAGGED', { tagType: dto.tagType, tagUid: dto.tagUid }, user.id);
      return tag;
    });
  }

  async attachImage(user: AuthUser, id: string, dto: AttachImageDto) {
    const batch = await this.loadForUser(user, id);
    Ownership.assertSite(user, batch.currentSiteId);
    const again = await this.prisma.batchImage.findFirst({ where: { batchId: id, s3Key: dto.key } });
    if (again) return again;
    const upload = await this.files.verifyOwnUpload(user, dto.key, 'BATCH_IMAGE');
    const image = await this.prisma.$transaction(async (tx) => {
      const row = await tx.batchImage.create({
        data: {
          batchId: id,
          view: dto.view,
          s3Key: dto.key,
          sizeBytes: upload.sizeBytes,
          width: dto.width,
          height: dto.height,
          capturedAt: new Date(dto.capturedAt),
        },
      });
      await this.trace.append(tx, id, 'IMAGED', { view: dto.view, key: dto.key, sizeBytes: upload.sizeBytes }, user.id, new Date(dto.capturedAt));
      return row;
    });
    await this.events.publish('quality-scans', id, { type: 'IMAGE_ATTACHED', batchId: id, view: dto.view, key: dto.key });
    return image;
  }

  // ───────────────────────── storage (SYN-10/20) ─────────────────────────

  async storagePath(user: AuthUser, id: string) {
    const batch = await this.loadForUser(user, id);
    const product = await this.prisma.product.findUniqueOrThrow({ where: { id: batch.productId } });
    return this.storage.recommend({ product, grade: batch.currentGrade, siteId: batch.currentSiteId, weightKg: Number(batch.weightKg) });
  }

  async assignStorage(user: AuthUser, id: string, unitId: string) {
    const batch = await this.loadForUser(user, id);
    Ownership.assertSite(user, batch.currentSiteId);
    if (!AT_SITE.includes(batch.status)) {
      fail('INVALID_STATUS', `Cannot store a batch with status ${batch.status}`, HttpStatus.CONFLICT);
    }
    const product = await this.prisma.product.findUniqueOrThrow({ where: { id: batch.productId } });
    const updated = await this.prisma.$transaction(async (tx) => {
      const unit = await this.storage.assign(tx, {
        unitId,
        siteId: batch.currentSiteId,
        product,
        weightKg: Number(batch.weightKg),
        previousUnitId: batch.storageUnitId,
      });
      const row = await tx.batch.update({ where: { id }, data: { storageUnitId: unit.id, status: 'STORED' } });
      if (batch.storageUnitId !== unit.id) {
        await this.trace.append(tx, id, 'STORED', { unitCode: unit.code, unitType: unit.type }, user.id);
      }
      return row;
    });
    return batchView(updated);
  }

  // ───────────────────────── receiving (FO-FR-10, SYN-19) ─────────────────────────

  /**
   * Receiving at the operator's site (inbound delivery or cross-dock). The receiving operator is
   * usually at a different site than the batch's current one, so no current-site ownership check.
   */
  async receive(user: AuthUser, id: string, dto: ReceiveDto) {
    if (user.role === 'OPERATOR' && !user.siteId) fail('NO_SITE', 'Operator is not linked to a site', HttpStatus.FORBIDDEN);
    const batch = await this.prisma.batch.findUnique({ where: { id } });
    if (!batch) fail('NOT_FOUND', 'Batch not found', HttpStatus.NOT_FOUND);
    if (['REJECTED', 'DELIVERED', 'SPOILED'].includes(batch.status)) {
      fail('INVALID_STATUS', `Cannot receive a batch with status ${batch.status}`, HttpStatus.CONFLICT);
    }
    const siteId = user.siteId ?? batch.currentSiteId;
    const weight = Number(batch.weightKg);
    const acceptedKg = dto.outcome === 'ACCEPTED' ? weight : dto.outcome === 'REJECTED' ? 0 : dto.acceptedKg;
    if (dto.outcome === 'PARTIAL' && !(acceptedKg > 0 && acceptedKg < weight)) {
      fail('INVALID_QUANTITY', `PARTIAL needs 0 < acceptedKg < ${weight}`, HttpStatus.BAD_REQUEST);
    }
    const uploads = await Promise.all((dto.imageKeys ?? []).map((k) => this.files.verifyOwnUpload(user, k, 'BATCH_IMAGE')));
    const site = siteId ? await this.prisma.site.findUnique({ where: { id: siteId }, select: { code: true } }) : null;

    const updated = await this.prisma.$transaction(async (tx) => {
      if (batch.storageUnitId) await this.storage.release(tx, batch.storageUnitId, weight);
      const status: BatchStatus = dto.outcome === 'REJECTED' ? 'REJECTED' : batch.currentGrade ? 'GRADED' : 'REGISTERED';
      const row = await tx.batch.update({
        where: { id },
        data: { currentSiteId: siteId, storageUnitId: null, status, ...(dto.outcome === 'PARTIAL' ? { weightKg: acceptedKg } : {}) },
      });
      const now = new Date();
      for (const u of uploads) {
        await tx.batchImage.create({
          data: {
            batchId: id,
            view: dto.outcome === 'ACCEPTED' ? 'RECEIVING' : 'DAMAGE',
            s3Key: u.key,
            sizeBytes: u.sizeBytes,
            width: 0, // not reported by the receive call; see API docs
            height: 0,
            capturedAt: now,
          },
        });
      }
      await this.trace.append(
        tx,
        id,
        dto.outcome === 'REJECTED' ? 'REJECTED' : 'RECEIVED',
        { siteCode: site?.code ?? null, outcome: dto.outcome, acceptedKg, condition: dto.condition, notes: dto.notes ?? null, imageKeys: dto.imageKeys ?? [] },
        user.id,
      );
      return row;
    });
    return batchView(updated);
  }

  // ───────────────────────── label, timeline, shelf life ─────────────────────────

  async label(user: AuthUser, id: string) {
    const batch = await this.loadForUser(user, id);
    const [product, site] = await Promise.all([
      this.prisma.product.findUniqueOrThrow({ where: { id: batch.productId } }),
      this.prisma.site.findUniqueOrThrow({ where: { id: batch.sourceSiteId } }),
    ]);
    const traceUrl = this.trace.traceUrl(batch.code);
    return {
      code: batch.code,
      product: { code: product.code, name: product.name, nameHi: product.nameHi, nameMr: product.nameMr },
      weightKg: Number(batch.weightKg),
      grade: batch.currentGrade,
      caughtOrHarvestedAt: batch.caughtOrHarvestedAt,
      sourceSite: { code: site.code, name: site.name },
      traceUrl,
      qrData: traceUrl,
    };
  }

  async timeline(user: AuthUser, id: string) {
    await this.loadForUser(user, id);
    const events = await this.trace.events(id);
    const verdict = await this.trace.verify(id);
    return {
      verified: verdict.valid,
      verification: verdict,
      events: events.map((e) => ({
        seq: e.seq,
        type: e.eventType,
        payload: e.payload,
        actorUserId: e.actorUserId,
        occurredAt: e.occurredAt,
        hash: e.hash,
      })),
    };
  }

  async shelfLife(user: AuthUser, id: string) {
    const batch = await this.loadForUser(user, id);
    const estimates = await this.prisma.shelfLifeEstimate.findMany({ where: { batchId: id }, orderBy: { createdAt: 'desc' }, take: 20 });
    return {
      remainingShelfLifeH: num(batch.remainingShelfLifeH),
      updatedAt: batch.shelfLifeUpdatedAt,
      estimates: estimates.map((e) => ({ ...e, remainingH: Number(e.remainingH) })),
    };
  }
}
