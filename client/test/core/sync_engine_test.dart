import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iccms/core/errors/app_exception.dart';
import 'package:iccms/core/storage/database.dart';
import 'package:iccms/core/sync/outbox_repository.dart';
import 'package:iccms/core/sync/sync_engine.dart';
import 'package:iccms/core/utils/backoff.dart';

/// A server that behaves like the backend's SyncService: idempotent on clientOpId, results per op.
class FakeServer implements SyncApi {
  final applied = <String, Map<String, dynamic>>{};
  final pushes = <List<Map<String, dynamic>>>[];
  final presigns = <String>[];
  final uploads = <String>[];

  /// Per-call behaviour overrides.
  AppException? failNextPush;
  bool dropNextResponse = false;
  AppException? failUpload;
  String Function(Map<String, dynamic> op)? decide; // APPLIED | REJECTED | UNSUPPORTED | ERROR

  @override
  Future<List<SyncResult>> push(List<Map<String, dynamic>> ops) async {
    pushes.add(ops);
    if (failNextPush != null) {
      final e = failNextPush!;
      failNextPush = null;
      throw e;
    }
    final results = <SyncResult>[];
    for (final op in ops) {
      final id = op['clientOpId'] as String;
      if (applied.containsKey(id)) {
        results.add(SyncResult(clientOpId: id, status: 'APPLIED', replayed: true));
        continue;
      }
      final status = decide?.call(op) ?? 'APPLIED';
      if (status == 'APPLIED') applied[id] = op;
      results.add(SyncResult(clientOpId: id, status: status, errorCode: status == 'APPLIED' ? null : 'X_$status', errorMessage: status));
    }
    if (dropNextResponse) {
      // The server applied everything but the response was lost (phone went into a tunnel).
      dropNextResponse = false;
      throw const AppException(AppException.network, 'connection reset');
    }
    return results;
  }

  @override
  Future<Presigned> presign({required String purpose, required String contentType, required int sizeBytes}) async {
    presigns.add(purpose);
    return Presigned(uploadUrl: 'https://s3/put', key: '$purpose/2026/11/${presigns.length}.jpg', headers: const {});
  }

  @override
  Future<void> upload(Presigned target, String localPath) async {
    if (failUpload != null) throw failUpload!;
    uploads.add(localPath);
  }
}

void main() {
  late AppDatabase db;
  late OutboxRepository outbox;
  late FakeServer server;
  late SyncEngine engine;
  var now = DateTime.utc(2026, 11, 14, 6);

  setUp(() {
    now = DateTime.utc(2026, 11, 14, 6);
    db = AppDatabase(NativeDatabase.memory());
    outbox = OutboxRepository(db, clock: () => now);
    server = FakeServer();
    engine = SyncEngine(db, server, clock: () => now, backoff: const Backoff(jitter: false), chunkSize: 50);
  });
  tearDown(() => db.close());

  Future<String> op(String entity, int minute, {String type = 'TRIP_EVENT', List<String> files = const [], Map<String, dynamic>? payload}) =>
      outbox.enqueue(type: type, entityId: entity, payload: payload ?? {'entity': entity, 'minute': minute}, fileIds: files, capturedAt: DateTime.utc(2026, 11, 14, 5, minute));

  Future<List<OutboxOp>> left() => db.select(db.outboxOps).get();

  test('ops go out in capture order (not insertion order) and are deleted only after APPLIED', () async {
    await op('t1', 30);
    await op('t2', 10);
    await op('t1', 20);
    final r = await engine.run();
    expect(server.pushes.single.map((o) => (o['payload'] as Map)['minute']), [10, 20, 30]);
    expect(server.pushes.single.first['capturedAt'], '2026-11-14T05:10:00.000Z');
    expect(r.applied, 3);
    expect(await left(), isEmpty);
  });

  test('chunks of 50', () async {
    for (var i = 0; i < 120; i++) {
      await op('e$i', i % 60);
    }
    await engine.run();
    expect(server.pushes.map((c) => c.length), [50, 50, 20]);
    expect(server.applied.length, 120);
  });

  test('airplane mode → reconnect: synced exactly once, even when the first response was lost', () async {
    await op('t1', 1);
    await op('t1', 2);
    server.failNextPush = const AppException(AppException.network, 'offline');
    final offline = await engine.run();
    expect(offline.stoppedBy, AppException.network);
    expect((await left()).length, 2, reason: 'nothing is deleted locally until the server confirms');
    expect((await left()).every((o) => o.attempts == 1 && o.nextAttemptAt!.isAtSameMomentAs(now.add(const Duration(seconds: 5)))), isTrue);

    // Back online but the response gets lost after the server applied the ops.
    now = now.add(const Duration(seconds: 6));
    server.dropNextResponse = true;
    await engine.run();
    expect(server.applied.length, 2);
    expect((await left()).length, 2);

    // Next pass: the server answers "replayed"; the ops are confirmed and removed. Applied once.
    now = now.add(const Duration(seconds: 11));
    final ok = await engine.run();
    expect(ok.applied, 2);
    expect(await left(), isEmpty);
    expect(server.applied.length, 2);
    expect(server.pushes.length, 3);
  });

  test('retry/backoff: 5 s doubling while the server errors, capped at 30 min', () async {
    await op('t1', 1);
    server.decide = (_) => 'ERROR';
    final waits = <Duration>[];
    for (var i = 0; i < 12; i++) {
      await engine.run();
      final o = (await left()).single;
      waits.add(o.nextAttemptAt!.difference(now));
      now = o.nextAttemptAt!;
    }
    expect(waits.take(4).map((d) => d.inSeconds), [5, 10, 20, 40]);
    expect(waits.last, const Duration(minutes: 30));
    final before = server.pushes.length;
    await engine.run();
    now = now.add(const Duration(minutes: 1));
    await engine.run();
    expect(server.pushes.length, before + 1, reason: 'not retried before nextAttemptAt');
  });

  test('a REJECTED op needs attention and holds back later ops of the same entity only', () async {
    final bad = await op('b1', 1, type: 'BATCH_UPDATE');
    await op('b1', 2, type: 'BATCH_UPDATE');
    await op('b2', 3, type: 'BATCH_UPDATE');
    server.decide = (o) => o['clientOpId'] == bad ? 'REJECTED' : 'APPLIED';
    final r = await engine.run();
    // Same chunk: b1's second op was sent together with the first (the server orders per entity).
    expect(r.needsAttention, 1);
    final rows = await left();
    expect(rows.single.clientOpId, bad);
    expect(rows.single.status, 'attention');
    expect(rows.single.lastErrorCode, 'X_REJECTED');

    // A new op on b1 waits behind the one needing attention; b3 goes through.
    await op('b1', 4, type: 'BATCH_UPDATE');
    await op('b3', 5, type: 'BATCH_UPDATE');
    server.pushes.clear();
    await engine.run();
    expect(server.pushes.single.map((o) => o['payload']['entity']), ['b3']);

    // The user fixes it and taps Retry: it goes out, then the held-back op.
    server.decide = null;
    await outbox.retry(bad);
    await engine.run();
    expect(await left(), isEmpty);
  });

  test('UNSUPPORTED (newer server feature) stays queued; a permanent 4xx on the request → needs attention', () async {
    await op('t1', 1, type: 'GPS_POINTS');
    server.decide = (_) => 'UNSUPPORTED';
    await engine.run();
    expect((await left()).single.status, 'pending');
    expect((await left()).single.nextAttemptAt, isNotNull);

    await db.delete(db.outboxOps).go();
    await op('t2', 1);
    server.decide = null;
    server.failNextPush = const AppException('VALIDATION_FAILED', 'bad envelope', status: 400);
    await engine.run();
    expect((await left()).single.status, 'attention');
  });

  test('files upload first; the S3 key replaces the placeholder; a failed file blocks only its op', () async {
    final f1 = await outbox.addFile(localPath: '/tmp/sig.png', purpose: 'POD_SIGNATURE', contentType: 'image/png', sizeBytes: 1000);
    await op('s1', 1, type: 'POD', files: [f1], payload: {'stopId': 's1', 'signatureKey': OutboxRepository.fileRef(f1)});
    await engine.run();
    expect(server.uploads, ['/tmp/sig.png']);
    final sent = server.pushes.single.single['payload'] as Map;
    expect(sent['signatureKey'], 'POD_SIGNATURE/2026/11/1.jpg');
    expect(await left(), isEmpty);

    // Upload refused for good (e.g. 413 too large): the file and its op need attention; others flow.
    final f2 = await outbox.addFile(localPath: '/tmp/big.jpg', purpose: 'POD_PHOTO', contentType: 'image/jpeg', sizeBytes: 9000000);
    await op('s2', 2, type: 'POD', files: [f2], payload: {'photoKey': OutboxRepository.fileRef(f2)});
    await op('s3', 3);
    server.failUpload = const AppException('HTTP_413', 'too large', status: 413);
    server.pushes.clear();
    await engine.run();
    final file = await (db.select(db.pendingFiles)..where((f) => f.id.equals(f2))).getSingle();
    expect(file.status, 'attention');
    expect(server.pushes.single.map((o) => o['payload']['entity']), ['s3']);
    final blocked = (await left()).single;
    expect([blocked.entityId, blocked.status, blocked.lastErrorCode], ['s2', 'attention', 'FILE_UPLOAD_FAILED']);
  });

  test('a write and its op are one transaction: if the write fails, nothing is queued', () async {
    await expectLater(
      outbox.enqueue(type: 'BATCH_CREATE', entityId: 'x', payload: {}, write: () async {
        await db.kvSet('batch:x', jsonEncode({'id': 'x'}));
        throw StateError('disk full');
      }),
      throwsStateError,
    );
    expect(await left(), isEmpty);
    expect(await db.kvGet('batch:x'), isNull);
  });

  test('concurrent run() calls share one pass', () async {
    await op('t1', 1);
    final a = engine.run();
    final b = engine.run();
    expect(identical(await a, await b), isTrue);
    expect(server.pushes.length, 1);
  });

  test('pending count stream for the badge', () async {
    final counts = <int>[];
    final sub = outbox.watchPendingCount().listen(counts.add);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await op('t1', 1);
    await op('t2', 2);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await engine.run();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    expect(counts.first, 0);
    expect(counts, containsAllInOrder([0, 2, 0]));
  });

  test('discard only removes ops the server rejected', () async {
    final id = await op('t1', 1);
    expect(await outbox.discard(id), 0);
    await (db.update(db.outboxOps)..where((t) => t.clientOpId.equals(id))).write(const OutboxOpsCompanion(status: Value('attention')));
    expect(await outbox.discard(id), 1);
  });
}
