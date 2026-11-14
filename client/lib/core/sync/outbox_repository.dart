import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../storage/database.dart';

/// Writes go here instead of straight to the API (Section 10.2): the caller updates its local
/// entity and enqueues the op in ONE transaction, so a crash never leaves one without the other.
class OutboxRepository {
  OutboxRepository(this.db, {DateTime Function()? clock, Uuid? uuid})
      : _now = clock ?? DateTime.now,
        _uuid = uuid ?? const Uuid();

  final AppDatabase db;
  final DateTime Function() _now;
  final Uuid _uuid;

  /// Placeholder for a file key inside an op payload: replaced with the S3 key after upload.
  static Map<String, String> fileRef(String pendingFileId) => {r'$file': pendingFileId};

  /// Run [write] (local entity changes) and enqueue the op atomically. Returns the clientOpId.
  Future<String> enqueue({
    required String type,
    required String entityId,
    required Map<String, dynamic> payload,
    List<String> fileIds = const [],
    DateTime? capturedAt,
    String? clientOpId,
    Future<void> Function()? write,
  }) {
    return db.transaction(() async {
      if (write != null) await write();
      final id = clientOpId ?? _uuid.v4();
      final now = _now();
      await db.into(db.outboxOps).insert(OutboxOpsCompanion.insert(
            clientOpId: id,
            type: type,
            entityId: entityId,
            payload: jsonEncode(payload),
            fileIds: Value(jsonEncode(fileIds)),
            capturedAt: (capturedAt ?? now).toUtc(),
            createdAt: now.toUtc(),
          ));
      return id;
    });
  }

  /// A local file to upload before the op that references it.
  Future<String> addFile({required String localPath, required String purpose, required String contentType, required int sizeBytes}) async {
    final id = _uuid.v4();
    await db.into(db.pendingFiles).insert(PendingFilesCompanion.insert(
          id: id,
          localPath: localPath,
          purpose: purpose,
          contentType: contentType,
          sizeBytes: sizeBytes,
          createdAt: _now().toUtc(),
        ));
    return id;
  }

  Stream<int> watchPendingCount() {
    final c = db.outboxOps.clientOpId.count();
    return (db.selectOnly(db.outboxOps)..addColumns([c])).map((r) => r.read(c) ?? 0).watchSingle();
  }

  Stream<List<OutboxOp>> watchAll() =>
      (db.select(db.outboxOps)..orderBy([(t) => OrderingTerm(expression: t.capturedAt), (t) => OrderingTerm(expression: t.createdAt)])).watch();

  Stream<List<PendingFile>> watchFiles() => (db.select(db.pendingFiles)..where((t) => t.status.isNotIn(['uploaded']))).watch();

  /// "Retry now" from the Sync Queue: a needs-attention op goes back to pending (the user fixed the cause).
  Future<void> retry(String clientOpId) => (db.update(db.outboxOps)..where((t) => t.clientOpId.equals(clientOpId)))
      .write(const OutboxOpsCompanion(status: Value('pending'), nextAttemptAt: Value(null)));

  /// "Discard" from the Sync Queue: only for ops the server rejected for good.
  Future<int> discard(String clientOpId) =>
      (db.delete(db.outboxOps)..where((t) => t.clientOpId.equals(clientOpId) & t.status.equals('attention'))).go();
}
