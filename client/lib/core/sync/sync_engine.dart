import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../errors/app_exception.dart';
import '../storage/database.dart';
import '../utils/backoff.dart';
import '../utils/single_flight.dart';

/// `/sync` result for one op (server SyncService).
class SyncResult {
  const SyncResult({required this.clientOpId, required this.status, this.replayed = false, this.errorCode, this.errorMessage});

  factory SyncResult.fromJson(Map<String, dynamic> j) => SyncResult(
        clientOpId: j['clientOpId'] as String,
        status: j['status'] as String,
        replayed: j['replayed'] == true,
        errorCode: (j['error'] as Map?)?['code'] as String?,
        errorMessage: (j['error'] as Map?)?['message'] as String?,
      );

  final String clientOpId;

  /// APPLIED | REJECTED | UNSUPPORTED | ERROR
  final String status;
  final bool replayed;
  final String? errorCode;
  final String? errorMessage;
}

class Presigned {
  const Presigned({required this.uploadUrl, required this.key, required this.headers});
  final String uploadUrl;
  final String key;
  final Map<String, String> headers;
}

/// The server side of syncing; [ApiSyncApi] talks to the backend, tests use a fake.
abstract class SyncApi {
  Future<List<SyncResult>> push(List<Map<String, dynamic>> ops);
  Future<Presigned> presign({required String purpose, required String contentType, required int sizeBytes});
  Future<void> upload(Presigned target, String localPath);
}

class SyncReport {
  int filesUploaded = 0;
  int applied = 0;
  int needsAttention = 0;
  int retryLater = 0;
  int sent = 0;
  String? stoppedBy;

  @override
  String toString() => 'SyncReport(files: $filesUploaded, sent: $sent, applied: $applied, attention: $needsAttention, retry: $retryLater, stoppedBy: $stoppedBy)';
}

/// Outbox sync (Section 10.2 core/sync):
/// 1. files first: presign → PUT, the S3 key replaces `{"$file": id}` in op payloads;
/// 2. ops in capture order, in chunks of 50; ops of one entity strictly in order — an earlier op
///    that is waiting or needs attention holds back the later ones;
/// 3. APPLIED (or replayed) → deleted locally (only now); REJECTED / permanent 4xx → "needs
///    attention"; UNSUPPORTED / ERROR / network / 5xx / 408 / 429 → retried with backoff (5 s
///    doubling, max 30 min).
/// The server is idempotent on clientOpId, so a lost response is simply sent again: synced once.
class SyncEngine {
  SyncEngine(this.db, this.api, {DateTime Function()? clock, Backoff backoff = syncBackoff, double Function()? random, this.chunkSize = 50})
      : _now = clock ?? DateTime.now,
        _backoff = backoff, // ignore: prefer_initializing_formals
        _random = random ?? math.Random().nextDouble;

  final AppDatabase db;
  final SyncApi api;
  final DateTime Function() _now;
  final Backoff _backoff;
  final double Function() _random;
  final int chunkSize;
  final _flight = SingleFlight<SyncReport>();

  bool get isRunning => _flight.isRunning;

  /// One pass. Concurrent callers share the running pass. [force] ignores the retry backoff of
  /// pending ops and files (connection regained, or the user tapped "Sync now"): the wait was only
  /// there because the network was gone. Ops needing attention still wait for the user.
  Future<SyncReport> run({bool force = false}) => _flight.run(() => _run(force));

  DateTime _retryAt(int attempts) => _now().toUtc().add(_backoff.delay(attempts, random: _random()));

  Future<SyncReport> _run(bool force) async {
    final report = SyncReport();
    if (!await _uploadFiles(report, force)) return report;
    await _pushOps(report, force);
    return report;
  }

  /// Returns false when the network is gone (stop the pass).
  Future<bool> _uploadFiles(SyncReport report, bool force) async {
    final now = force ? DateTime.utc(9999) : _now().toUtc();
    final due = await (db.select(db.pendingFiles)
          ..where((f) => f.status.equals('pending') & (f.nextAttemptAt.isNull() | f.nextAttemptAt.isSmallerOrEqualValue(now)))
          ..orderBy([(f) => OrderingTerm(expression: f.createdAt)]))
        .get();
    for (final f in due) {
      try {
        final target = await api.presign(purpose: f.purpose, contentType: f.contentType, sizeBytes: f.sizeBytes);
        await api.upload(target, f.localPath);
        await (db.update(db.pendingFiles)..where((t) => t.id.equals(f.id)))
            .write(PendingFilesCompanion(status: const Value('uploaded'), remoteKey: Value(target.key), lastError: const Value(null)));
        report.filesUploaded++;
      } on AppException catch (e) {
        final attempts = f.attempts + 1;
        await (db.update(db.pendingFiles)..where((t) => t.id.equals(f.id))).write(PendingFilesCompanion(
              attempts: Value(attempts),
              status: Value(e.isPermanent ? 'attention' : 'pending'),
              nextAttemptAt: Value(e.isPermanent ? null : _retryAt(attempts)),
              lastError: Value('${e.code}: ${e.message}'),
            ));
        if (e.status == null) {
          report.stoppedBy = e.code;
          return false;
        }
      }
    }
    return true;
  }

  Future<void> _pushOps(SyncReport report, bool force) async {
    final now = force ? DateTime.utc(9999) : _now().toUtc();
    final ops = await (db.select(db.outboxOps)..orderBy([(o) => OrderingTerm(expression: o.capturedAt), (o) => OrderingTerm(expression: o.createdAt)])).get();
    final files = {for (final f in await db.select(db.pendingFiles).get()) f.id: f};

    final blocked = <String>{};
    final ready = <({OutboxOp op, Map<String, dynamic> wire})>[];
    for (final op in ops) {
      if (blocked.contains(op.entityId)) continue;
      if (op.status == 'attention' || (op.nextAttemptAt != null && op.nextAttemptAt!.isAfter(now))) {
        blocked.add(op.entityId);
        continue;
      }
      final needed = (jsonDecode(op.fileIds) as List).cast<String>();
      final missing = needed.where((id) => files[id]?.status != 'uploaded').toList();
      if (missing.isNotEmpty) {
        if (missing.any((id) => files[id] == null || files[id]!.status == 'attention')) {
          await _attention(op, 'FILE_UPLOAD_FAILED', 'A file of this record could not be uploaded');
          report.needsAttention++;
        }
        blocked.add(op.entityId);
        continue;
      }
      final payload = _resolveFiles(jsonDecode(op.payload), files);
      ready.add((op: op, wire: {'clientOpId': op.clientOpId, 'type': op.type, 'payload': payload, 'capturedAt': op.capturedAt.toUtc().toIso8601String()}));
    }

    // An entity blocked by a failure in an earlier chunk is held back; ops in the same chunk as the
    // failure were sent together and the server applies them in order itself.
    for (var i = 0; i < ready.length; i += chunkSize) {
      final chunk = ready.sublist(i, math.min(i + chunkSize, ready.length)).where((r) => !blocked.contains(r.op.entityId)).toList();
      if (chunk.isEmpty) continue;
      report.sent += chunk.length;
      List<SyncResult> results;
      try {
        results = await api.push(chunk.map((r) => r.wire).toList());
      } on AppException catch (e) {
        if (e.isPermanent && e.code != AppException.sessionOnOtherDevice && e.status != 401) {
          for (final r in chunk) {
            await _attention(r.op, e.code, e.message);
          }
          report.needsAttention += chunk.length;
          continue;
        }
        for (final r in chunk) {
          await _later(r.op, e.code, e.message);
        }
        report.retryLater += chunk.length;
        report.stoppedBy = e.code;
        return;
      }
      final byId = {for (final r in results) r.clientOpId: r};
      for (final r in chunk) {
        final res = byId[r.op.clientOpId];
        if (res == null) {
          await _later(r.op, 'NO_RESULT', 'The server did not answer for this op');
          report.retryLater++;
        } else if (res.status == 'APPLIED') {
          await (db.delete(db.outboxOps)..where((t) => t.clientOpId.equals(r.op.clientOpId))).go();
          report.applied++;
        } else if (res.status == 'REJECTED') {
          await _attention(r.op, res.errorCode ?? 'REJECTED', res.errorMessage ?? 'Rejected by the server');
          blocked.add(r.op.entityId);
          report.needsAttention++;
        } else {
          // UNSUPPORTED (newer server feature) or ERROR (temporary): keep it, try later.
          await _later(r.op, res.errorCode ?? res.status, res.errorMessage ?? res.status);
          blocked.add(r.op.entityId);
          report.retryLater++;
        }
      }
    }
  }

  Future<void> _attention(OutboxOp op, String code, String message) =>
      (db.update(db.outboxOps)..where((t) => t.clientOpId.equals(op.clientOpId))).write(OutboxOpsCompanion(
            status: const Value('attention'),
            attempts: Value(op.attempts + 1),
            nextAttemptAt: const Value(null),
            lastErrorCode: Value(code),
            lastError: Value(message),
          ));

  Future<void> _later(OutboxOp op, String code, String message) {
    final attempts = op.attempts + 1;
    return (db.update(db.outboxOps)..where((t) => t.clientOpId.equals(op.clientOpId))).write(OutboxOpsCompanion(
          attempts: Value(attempts),
          nextAttemptAt: Value(_retryAt(attempts)),
          lastErrorCode: Value(code),
          lastError: Value(message),
        ));
  }

  static dynamic _resolveFiles(dynamic node, Map<String, PendingFile> files) {
    if (node is Map) {
      if (node.length == 1 && node.containsKey(r'$file')) return files[node[r'$file']]?.remoteKey;
      return node.map((k, v) => MapEntry(k, _resolveFiles(v, files)));
    }
    if (node is List) return node.map((v) => _resolveFiles(v, files)).toList();
    return node;
  }
}
