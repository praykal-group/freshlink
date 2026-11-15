import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/database.dart';
import '../../../core/sync/outbox_repository.dart';
import '../../../core/tags/tag_reader.dart';
import '../../../core/printing/label_printer.dart';
import 'models.dart';

/// Form values of a new batch (FO-FR-02/03).
class BatchDraft {
  const BatchDraft({
    required this.productId, required this.caughtOrHarvestedAt, required this.weightKg, this.vesselId, this.farmRef, this.iceToFishRatio,
    this.initialCoreTemp, this.maturityIndex, this.brix, this.fieldTemp, this.fieldHumidity,
  });

  final String productId;
  final DateTime caughtOrHarvestedAt;
  final double weightKg;
  final String? vesselId;
  final String? farmRef;
  final double? iceToFishRatio;
  final double? initialCoreTemp;
  final double? maturityIndex;
  final double? brix;
  final double? fieldTemp;
  final double? fieldHumidity;

  Map<String, dynamic> toFields() => {
        'caughtOrHarvestedAt': caughtOrHarvestedAt.toUtc().toIso8601String(),
        'weightKg': weightKg,
        'vesselId': ?vesselId,
        'farmRef': ?farmRef,
        'iceToFishRatio': ?iceToFishRatio,
        'initialCoreTemp': ?initialCoreTemp,
        'maturityIndex': ?maturityIndex,
        'brix': ?brix,
        'fieldTemp': ?fieldTemp,
        'fieldHumidity': ?fieldHumidity,
      };
}

class ReceiveInput {
  const ReceiveInput({required this.outcome, required this.acceptedKg, required this.condition, this.notes, this.photoFileIds = const []});
  final String outcome; // ACCEPTED | PARTIAL | REJECTED
  final double acceptedKg;
  final String condition; // GOOD | FAIR | POOR
  final String? notes;
  final List<String> photoFileIds;
}

const _mastersKind = 'bundle';
const _summaryKey = 'operator.summary';
const _tripsKey = 'operator.trips';
const _pendingGradesKey = 'operator.pendingGrades';
String _lastUsedKey(String category) => 'operator.last.$category';

/// Everything the operator app reads and writes. Writes that must work offline go through the
/// outbox (BATCH_CREATE, TAG_ATTACH, IMAGE_ATTACH, BATCH_UPDATE, RECEIVE, LOAD: one entity per
/// batch/trip so they apply in order); the rest needs the network and says so (AppException).
class OperatorRepository {
  OperatorRepository({required this.api, required this.db, required this.outbox, Uuid? uuid, DateTime Function()? clock})
      : _uuid = uuid ?? const Uuid(),
        _now = clock ?? DateTime.now;

  final ApiClient api;
  final AppDatabase db;
  final OutboxRepository outbox;
  final Uuid _uuid;
  final DateTime Function() _now;

  // ───────────── masters (FO-FR-04) ─────────────

  Future<Masters> masters({bool refresh = true}) async {
    if (refresh) {
      try {
        final json = Map<String, dynamic>.from(await api.get('/masters/bundle') as Map);
        await db.into(db.cachedMasters).insertOnConflictUpdate(CachedMastersCompanion.insert(kind: _mastersKind, payload: jsonEncode(json), updatedAt: _now().toUtc()));
        return Masters.fromJson(json, fetchedAt: _now());
      } on AppException catch (e) {
        if (!e.isTransient) rethrow;
      }
    }
    final cached = await (db.select(db.cachedMasters)..where((m) => m.kind.equals(_mastersKind))).getSingleOrNull();
    if (cached == null) throw const AppException(AppException.network, 'Master lists are not downloaded yet');
    return Masters.fromJson(jsonDecode(cached.payload) as Map<String, dynamic>, fetchedAt: cached.updatedAt, fromCache: true);
  }

  Future<Map<String, dynamic>> lastUsed(String category) async {
    final v = await db.kvGet(_lastUsedKey(category));
    return v == null ? {} : Map<String, dynamic>.from(jsonDecode(v) as Map);
  }

  Future<void> saveLastUsed(String category, Map<String, dynamic> values) => db.kvSet(_lastUsedKey(category), jsonEncode(values));

  // ───────────── home ─────────────

  Future<OperatorSummary> summary() async {
    try {
      final s = OperatorSummary.fromJson(Map<String, dynamic>.from(await api.get('/operator/summary') as Map));
      await db.kvSet(_summaryKey, jsonEncode(s.toJson()));
      return s;
    } on AppException catch (e) {
      final cached = await db.kvGet(_summaryKey);
      if (e.isTransient && cached != null) return OperatorSummary.fromJson(jsonDecode(cached) as Map<String, dynamic>);
      rethrow;
    }
  }

  // ───────────── batch registration (offline-first) ─────────────

  /// Creates the batch locally and queues BATCH_CREATE. The id is the client UUID the server keeps.
  Future<String> createBatch(BatchDraft d, {String? id}) async {
    final batchId = id ?? _uuid.v4();
    final now = _now().toUtc();
    final payload = {'id': batchId, 'productId': d.productId, 'capturedAt': now.toIso8601String(), ...d.toFields()};
    await outbox.enqueue(
      type: 'BATCH_CREATE',
      entityId: batchId,
      payload: payload,
      capturedAt: now,
      write: () => db.into(db.cachedBatches).insertOnConflictUpdate(CachedBatchesCompanion.insert(
            id: batchId,
            payload: jsonEncode({...payload, 'status': 'REGISTERED', 'createdAt': now.toIso8601String(), 'code': null}),
            updatedAt: now,
          )),
    );
    return batchId;
  }

  Future<void> attachTag(String batchId, TagRead tag) =>
      outbox.enqueue(type: 'TAG_ATTACH', entityId: batchId, payload: {'batchId': batchId, 'tagType': tag.kind.api, 'tagUid': tag.uid});

  /// A compressed photo (FO-NFR-04) queued for upload + IMAGE_ATTACH. Returns the pending file id.
  Future<String> addPhoto({required String batchId, required String view, required String localPath, required int sizeBytes, required int width, required int height, DateTime? capturedAt}) async {
    final fileId = await outbox.addFile(localPath: localPath, purpose: 'BATCH_IMAGE', contentType: 'image/jpeg', sizeBytes: sizeBytes);
    final at = (capturedAt ?? _now()).toUtc();
    await outbox.enqueue(
      type: 'IMAGE_ATTACH',
      entityId: batchId,
      fileIds: [fileId],
      capturedAt: at,
      payload: {'batchId': batchId, 'view': view, 'key': OutboxRepository.fileRef(fileId), 'width': width, 'height': height, 'capturedAt': at.toIso8601String()},
    );
    return fileId;
  }

  /// No op of this batch waits in the outbox: the server has everything the phone recorded.
  Future<bool> isSynced(String batchId) async {
    final left = await (db.select(db.outboxOps)..where((o) => o.entityId.equals(batchId))).get();
    return left.isEmpty;
  }

  // ───────────── grading (FO-FR-07) ─────────────

  Future<GradeResult> grade(String batchId) async => GradeResult.fromJson(Map<String, dynamic>.from(await api.post('/batches/$batchId/grade') as Map));

  Future<void> dispute(String batchId, String reason) => api.post('/batches/$batchId/grade/dispute', body: {'reason': reason});

  /// Offline registration: the grade is requested once the batch and its photos reached the server.
  Future<void> queueGrade(String batchId) async {
    final list = await pendingGrades();
    if (!list.contains(batchId)) await db.kvSet(_pendingGradesKey, jsonEncode([...list, batchId]));
  }

  Future<List<String>> pendingGrades() async {
    final v = await db.kvGet(_pendingGradesKey);
    return v == null ? [] : (jsonDecode(v) as List).cast<String>();
  }

  /// Called after each sync pass. Grades batches whose data is on the server; a missing model (503)
  /// or no network keeps them queued; anything else (e.g. batch delivered) drops them.
  Future<Map<String, GradeResult>> processPendingGrades() async {
    final done = <String, GradeResult>{};
    final keep = <String>[];
    for (final id in await pendingGrades()) {
      if (!await isSynced(id)) {
        keep.add(id);
        continue;
      }
      try {
        done[id] = await grade(id);
      } on AppException catch (e) {
        if (e.isTransient || e.status == 503) keep.add(id);
      }
    }
    await db.kvSet(_pendingGradesKey, jsonEncode(keep));
    return done;
  }

  // ───────────── storage + label (FO-FR-08/09, online) ─────────────

  Future<StoragePath> storagePath(String batchId) async => StoragePath.fromJson(Map<String, dynamic>.from(await api.get('/batches/$batchId/storage-path') as Map));

  Future<void> assignStorage(String batchId, String unitId) => api.post('/batches/$batchId/storage', body: {'storageUnitId': unitId});

  Future<LabelData> label(String batchId) async => LabelData.fromJson(Map<String, dynamic>.from(await api.get('/batches/$batchId/label') as Map));

  // ───────────── list / detail / edit (FO-FR-12/13) ─────────────

  /// Server page, plus (on the first page) batches registered on this phone that are not synced yet.
  Future<({List<BatchItem> items, String? nextCursor})> list({String? status, String? q, String? cursor}) async {
    final local = cursor == null ? await localPendingBatches() : <BatchItem>[];
    try {
      final r = Map<String, dynamic>.from(await api.get('/batches', query: {'status': ?status, 'q': (q == null || q.isEmpty) ? null : q, 'cursor': ?cursor, 'limit': 30}..removeWhere((_, v) => v == null)) as Map);
      final server = [for (final b in r['items'] as List) BatchItem.fromJson(Map<String, dynamic>.from(b as Map))];
      final ids = server.map((b) => b.id).toSet();
      return (items: [...local.where((b) => !ids.contains(b.id) && _matches(b, status, q)), ...server], nextCursor: r['nextCursor'] as String?);
    } on AppException catch (e) {
      if (!e.isTransient || cursor != null) rethrow;
      return (items: local.where((b) => _matches(b, status, q)).toList(), nextCursor: null);
    }
  }

  bool _matches(BatchItem b, String? status, String? q) =>
      (status == null || b.status == status) && (q == null || q.isEmpty || b.displayCode.toLowerCase().contains(q.toLowerCase()) || b.id.startsWith(q));

  Future<List<BatchItem>> localPendingBatches() async {
    final pendingIds = (await (db.selectOnly(db.outboxOps, distinct: true)
              ..addColumns([db.outboxOps.entityId])
              ..where(db.outboxOps.type.equals('BATCH_CREATE')))
            .get())
        .map((r) => r.read(db.outboxOps.entityId)!)
        .toSet();
    if (pendingIds.isEmpty) return [];
    final rows = await (db.select(db.cachedBatches)..where((b) => b.id.isIn(pendingIds))).get();
    return [for (final r in rows) BatchItem.fromJson(jsonDecode(r.payload) as Map<String, dynamic>, pending: true)]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<Map<String, dynamic>> detail(String id) async => Map<String, dynamic>.from(await api.get('/batches/$id') as Map);

  Future<Map<String, dynamic>> timeline(String id) async => Map<String, dynamic>.from(await api.get('/batches/$id/timeline') as Map);

  /// Within 30 min: a direct correction (queued, works offline). The server re-checks the window
  /// against the original capture time and answers EDIT_WINDOW_CLOSED if it has passed.
  Future<void> update(String batchId, Map<String, dynamic> changes) =>
      outbox.enqueue(type: 'BATCH_UPDATE', entityId: batchId, payload: {'batchId': batchId, ...changes});

  /// After 30 min: an edit request for the manager (online).
  Future<void> requestEdit(String batchId, Map<String, dynamic> changes, String reason) => api.post('/batches/$batchId/edit-requests', body: {'changes': changes, 'reason': reason});

  // ───────────── receive (FO-FR-10) ─────────────

  /// Finds a batch by tag UID or batch code (label QR) on the server.
  Future<BatchItem?> findByScan(String value) async {
    final r = Map<String, dynamic>.from(await api.get('/batches', query: {'q': value, 'limit': 5}) as Map);
    final items = [for (final b in r['items'] as List) BatchItem.fromJson(Map<String, dynamic>.from(b as Map))];
    return items.where((b) => b.code == value).firstOrNull ?? items.firstOrNull;
  }

  Future<void> receive(String batchId, ReceiveInput input) => outbox.enqueue(
        type: 'RECEIVE',
        entityId: batchId,
        fileIds: input.photoFileIds,
        payload: {
          'batchId': batchId,
          'outcome': input.outcome,
          'acceptedKg': input.acceptedKg,
          'condition': input.condition,
          if (input.notes != null && input.notes!.trim().isNotEmpty) 'notes': input.notes!.trim(),
          if (input.photoFileIds.isNotEmpty) 'imageKeys': [for (final f in input.photoFileIds) OutboxRepository.fileRef(f)],
        },
      );

  Future<String> addReceivePhoto(String localPath, int sizeBytes) =>
      outbox.addFile(localPath: localPath, purpose: 'BATCH_IMAGE', contentType: 'image/jpeg', sizeBytes: sizeBytes);

  // ───────────── load truck (FO-FR-11) ─────────────

  Future<List<OperatorTrip>> trips() async {
    try {
      final r = Map<String, dynamic>.from(await api.get('/operator/trips') as Map);
      await db.kvSet(_tripsKey, jsonEncode(r));
      return [for (final t in r['items'] as List) OperatorTrip.fromJson(Map<String, dynamic>.from(t as Map))];
    } on AppException catch (e) {
      final cached = await db.kvGet(_tripsKey);
      if (!e.isTransient || cached == null) rethrow;
      return [for (final t in (jsonDecode(cached) as Map)['items'] as List) OperatorTrip.fromJson(Map<String, dynamic>.from(t as Map))];
    }
  }

  /// Queues LOAD for the scanned batch ids (the server re-checks the wrong-batch rule).
  Future<void> load(String tripId, List<String> batchIds) => outbox.enqueue(type: 'LOAD', entityId: tripId, payload: {'tripId': tripId, 'batchIds': batchIds});
}

/// A wizard in progress, saved after every step so it can be resumed (Section 10.4).
class WizardDraft {
  WizardDraft({required this.category, this.step = 0, this.batchId, Map<String, dynamic>? form, this.tag, Map<String, String>? photos, this.gradeQueued = false, this.grade, this.storageUnitCode, this.startedAt})
      : form = form ?? {},
        photos = photos ?? {};

  factory WizardDraft.fromJson(Map<String, dynamic> j) => WizardDraft(
        category: j['category'] as String,
        step: j['step'] as int? ?? 0,
        batchId: j['batchId'] as String?,
        form: Map<String, dynamic>.from(j['form'] as Map? ?? {}),
        tag: j['tag'] == null ? null : TagRead(TagKind.values.byName(j['tag']['kind'] as String), j['tag']['uid'] as String),
        photos: Map<String, String>.from(j['photos'] as Map? ?? {}),
        gradeQueued: j['gradeQueued'] == true,
        grade: j['grade'] as String?,
        storageUnitCode: j['storageUnitCode'] as String?,
        startedAt: j['startedAt'] == null ? null : DateTime.parse(j['startedAt'] as String),
      );

  final String category; // FISH | PRODUCE
  int step;
  String? batchId;
  Map<String, dynamic> form;
  TagRead? tag;

  /// view (TOP/SIDE/CLOSEUP) → local compressed file path
  Map<String, String> photos;
  bool gradeQueued;
  String? grade;
  String? storageUnitCode;

  /// For the < 60 s target (FO-NFR-03): when the operator started this batch.
  DateTime? startedAt;

  Map<String, dynamic> toJson() => {
        'category': category, 'step': step, 'batchId': batchId, 'form': form,
        'tag': tag == null ? null : {'kind': tag!.kind.name, 'uid': tag!.uid},
        'photos': photos, 'gradeQueued': gradeQueued, 'grade': grade, 'storageUnitCode': storageUnitCode, 'startedAt': startedAt?.toIso8601String(),
      };
}

const _draftKey = 'operator.wizard';

extension WizardDraftStore on AppDatabase {
  Future<WizardDraft?> loadDraft() async {
    final v = await kvGet(_draftKey);
    return v == null ? null : WizardDraft.fromJson(jsonDecode(v) as Map<String, dynamic>);
  }

  Future<void> saveDraft(WizardDraft d) => kvSet(_draftKey, jsonEncode(d.toJson()));

  Future<void> clearDraft() => (delete(kv)..where((k) => k.key.equals(_draftKey))).go();
}
