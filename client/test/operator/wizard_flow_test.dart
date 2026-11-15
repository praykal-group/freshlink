import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:iccms/apps/operator/data/operator_repository.dart';
import 'package:iccms/apps/operator/providers.dart';
import 'package:iccms/apps/operator/router.dart';
import 'package:iccms/apps/operator/screens/camera_screen.dart';
import 'package:iccms/bootstrap.dart';
import 'package:iccms/core/config/app_flavor.dart';
import 'package:iccms/core/providers.dart';
import 'package:iccms/core/router/app_router.dart';
import 'package:iccms/core/storage/database.dart';
import 'package:iccms/core/sync/api_sync_api.dart';
import 'package:iccms/core/sync/sync_engine.dart';
import 'package:iccms/core/sync/sync_scheduler.dart';
import 'package:iccms/core/tags/tag_reader.dart';

import '../helpers.dart';
import 'fake_server.dart';

/// Uploads from memory (the widget-test clock does not run real file IO).
class _MemSyncApi extends ApiSyncApi {
  _MemSyncApi(super.api);
  @override
  Future<void> upload(Presigned target, String localPath) => api.putToPresignedUrl(target.uploadUrl, Stream.value(const [0xff, 0xd8, 0xff]), target.headers);
}

class _FakeReader implements TagReader {
  const _FakeReader(this.kind, this.uid);
  @override
  final TagKind kind;
  final String uid;
  @override
  Future<TagRead?> read(BuildContext context) async => TagRead(kind, uid);
}

/// Section 16 / M11: "integration test of the full wizard online and offline" — the real screens,
/// outbox, sync engine and API client against a scripted backend.
void main() {
  late FakeIccmsServer server;
  late AppDatabase db;
  late ProviderContainer c;

  Future<void> run(WidgetTester t, [int ticks = 12]) async {
    for (var i = 0; i < ticks; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  /// Awaits [f] while advancing the test clock (dio, drift and backoff timers run on it).
  Future<T> drive<T>(WidgetTester t, Future<T> f) async {
    T? value;
    Object? error;
    var done = false;
    f.then((v) {
      value = v;
      done = true;
    }, onError: (Object e) {
      error = e;
      done = true;
    });
    for (var i = 0; i < 300 && !done; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    if (error != null) throw error!;
    if (!done) throw StateError('future did not complete');
    return value as T;
  }

  Future<void> boot(WidgetTester t) async {
    t.view.physicalSize = const Size(1080, 4800); // 360×1600 dp: every form field is built
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    server = FakeIccmsServer();
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    var shots = 0;
    c = ProviderContainer(overrides: [
      ...overridesFor(AppFlavor.operator, backend: FakeAuthBackend()..session = true, adapter: server.adapter, router: const OperatorRouter()).cast<Override>(),
      databaseProvider.overrideWithValue(db),
      syncSchedulerProvider.overrideWith((ref) => SyncScheduler(SyncEngine(ref.watch(databaseProvider)!, _MemSyncApi(ref.watch(apiClientProvider))))),
      tagReadersProvider.overrideWithValue(const {
        TagKind.nfc: _FakeReader(TagKind.nfc, '04A1B2C3D4E5F6'),
        TagKind.qr: _FakeReader(TagKind.qr, 'FSH-20261115-DCK-PTN-0001'),
        TagKind.uhf: _FakeReader(TagKind.uhf, 'E20034120123'),
      }),
      photoCaptureProvider.overrideWithValue((context, {required title, required instruction, required fileStem}) async {
        shots++;
        // A compressed photo as the camera screen returns it (size measured in operator_units_test).
        return CapturedPhoto(path: 'missing/$fileStem.jpg', originalPath: 'missing/$fileStem.orig.jpg', sizeBytes: 380 * 1024 + shots, width: 1280, height: 960, capturedAt: DateTime.now());
      }),
    ]);
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(container: c, child: const IccmsApp()));
    await run(t, 20);
  }

  Future<void> fillForm(WidgetTester t) async {
    unawaited(c.read(routerProvider).push('/batch/new/fish'));
    await run(t);
    await t.tap(find.byKey(const Key('product-ROHU')));
    // The first enterText right after the chip tap is dropped by the test text input (harness quirk),
    // so the core temperature is entered twice.
    await t.enterText(find.byKey(const Key('coreTemp')), '2.5');
    await t.pump();
    await t.enterText(find.byKey(const Key('weightKg')), '120');
    await t.pump();
    await t.enterText(find.byKey(const Key('coreTemp')), '2.5');
    await t.pump();
    await t.tap(find.byKey(const Key('form-next')));
    await run(t);
  }

  Future<void> tagAndPhotos(WidgetTester t) async {
    await t.tap(find.byKey(const Key('tag-nfc')));
    await run(t, 3);
    expect(find.byKey(const Key('tag-current')), findsOneWidget);
    await t.tap(find.byKey(const Key('tag-next')));
    await run(t);
    for (final v in ['Top', 'Side', 'Close-up']) {
      await t.tap(find.text(v));
      await run(t, 3);
    }
    await t.tap(find.byKey(const Key('photos-next')));
    // Wait for the grade step's outcome: a grade card or "queued".
    for (var i = 0; i < 100 && find.byKey(const Key('grade-next')).evaluate().isNotEmpty && find.textContaining('Grade ').evaluate().isEmpty && find.byKey(const Key('grade-queued')).evaluate().isEmpty; i++) {
      await run(t, 2);
    }
    await run(t, 3);
  }

  testWidgets('online: form → NFC tag → 3 photos → graded A → stored → label → done', (t) async {
    await boot(t);
    expect(find.text('iccms-module-operator'), findsOneWidget);
    final started = DateTime.now();
    await fillForm(t);
    await tagAndPhotos(t);
    // Grade step synced the batch and graded it.
    expect(find.text('Grade A'), findsOneWidget);
    expect(server.appliedTypes, ['BATCH_CREATE', 'TAG_ATTACH', 'IMAGE_ATTACH', 'IMAGE_ATTACH', 'IMAGE_ATTACH']);
    final create = server.applied.values.firstWhere((o) => o['type'] == 'BATCH_CREATE');
    final batchId = create['payload']['id'] as String;
    expect(create['payload'], containsPair('productId', FakeIccmsServer.rohuId));
    expect(create['payload'], containsPair('weightKg', 120.0));
    expect(create['payload'], containsPair('initialCoreTemp', 2.5));
    final images = server.applied.values.where((o) => o['type'] == 'IMAGE_ATTACH').map((o) => o['payload'] as Map).toList();
    expect(images.map((p) => p['view']).toSet(), {'TOP', 'SIDE', 'CLOSEUP'});
    expect(images.every((p) => (p['key'] as String).startsWith('BATCH_IMAGE/') && p['width'] == 1280), isTrue, reason: 'S3 keys replaced the placeholders');
    expect(server.uploads.length, 3);
    expect(server.gradeCalls, [batchId]);

    await t.tap(find.byKey(const Key('grade-next')));
    await run(t);
    expect(find.byKey(const Key('storage-path')), findsOneWidget);
    expect(find.text('Blast chiller'), findsOneWidget);
    await t.tap(find.byKey(const Key('assign')));
    await run(t);
    expect(server.storageAssigned[batchId], 'u-bc1');
    await t.tap(find.byKey(const Key('storage-next')));
    await run(t);
    expect(find.byKey(const Key('label-code')), findsOneWidget);
    expect(find.byKey(const Key('print')), findsOneWidget);
    expect(find.byKey(const Key('share-label')), findsOneWidget);
    await t.tap(find.byKey(const Key('label-next')));
    await run(t);
    expect(find.byKey(const Key('done-time')), findsOneWidget);
    expect(await drive(t, db.loadDraft()), isNull, reason: 'draft cleared when done');
    expect(DateTime.now().difference(started).inSeconds, lessThan(60), reason: 'machine time of the flow, not an operator timing');
  });

  testWidgets('offline: everything queued; after reconnect synced exactly once and graded', (t) async {
    await boot(t);
    await drive(t, c.read(mastersProvider.future)); // masters downloaded while online
    server.online = false;
    await fillForm(t);
    await tagAndPhotos(t);

    expect(find.byKey(const Key('grade-queued')), findsOneWidget);
    expect(server.applied, isEmpty);
    final repo = c.read(operatorRepositoryProvider);
    final queued = await drive(t, db.select(db.outboxOps).get());
    expect(queued.map((o) => o.type).toList(), ['BATCH_CREATE', 'TAG_ATTACH', 'IMAGE_ATTACH', 'IMAGE_ATTACH', 'IMAGE_ATTACH']);
    final batchId = queued.first.entityId;
    expect(queued.every((o) => o.entityId == batchId), isTrue, reason: 'one entity → applied in order');
    expect(await drive(t, repo.pendingGrades()), [batchId]);

    await t.tap(find.byKey(const Key('grade-next')));
    await run(t);
    expect(find.text('Blast chiller'), findsOneWidget, reason: 'storage path from the cached lists');
    expect(find.byKey(const Key('assign')), findsNothing);
    await t.tap(find.byKey(const Key('storage-next')));
    await run(t);
    expect(find.byKey(const Key('label-offline')), findsOneWidget);
    await t.tap(find.byKey(const Key('label-next')));
    await run(t);
    expect(find.byKey(const Key('done-time')), findsOneWidget);
    expect((await drive(t, repo.localPendingBatches())).map((b) => b.id), [batchId], reason: 'shown in the batch list as "not synced yet"');

    // Back online: one forced pass (reconnect), then the grade queue runs.
    server.online = true;
    await drive(t, c.read(syncSchedulerProvider)!.syncNow());
    await run(t, 3);
    expect(server.appliedTypes, ['BATCH_CREATE', 'TAG_ATTACH', 'IMAGE_ATTACH', 'IMAGE_ATTACH', 'IMAGE_ATTACH']);
    expect(await drive(t, db.select(db.outboxOps).get()), isEmpty);
    // The app's post-sync grade worker (home screen) grades the batch now that its data is on the server.
    await drive(t, repo.processPendingGrades());
    expect(server.gradeCalls, [batchId]);
    expect(await drive(t, repo.pendingGrades()), isEmpty);

    // Another pass sends nothing new: exactly once.
    final calls = server.syncCalls.length;
    await drive(t, c.read(syncSchedulerProvider)!.syncNow());
    await run(t, 3);
    expect(server.syncCalls.length, calls);
    expect(server.applied.length, 5);
  });

  testWidgets('no vision model on the server (503): grading is queued, not lost', (t) async {
    await boot(t);
    server.gradeModelMissing = true;
    await fillForm(t);
    await tagAndPhotos(t);
    expect(find.byKey(const Key('grade-queued')), findsOneWidget);
    expect(find.textContaining('not available right now'), findsOneWidget);
    expect(server.applied.length, 5, reason: 'the batch itself is on the server');
    expect((await drive(t, c.read(operatorRepositoryProvider).pendingGrades())).length, 1);
  });

  testWidgets('a wizard closed half-way resumes at the same step with the same batch', (t) async {
    await boot(t);
    await fillForm(t);
    final draft = (await drive(t, db.loadDraft()))!;
    expect(draft.step, 1);
    expect(draft.batchId, isNotNull);
    c.read(routerProvider).go('/home');
    await run(t);
    expect(find.byKey(const Key('resume-draft')), findsOneWidget);
    await t.tap(find.byKey(const Key('resume-draft')));
    await run(t);
    expect(find.byKey(const Key('tag-nfc')), findsOneWidget);
    expect((await drive(t, db.loadDraft()))!.batchId, draft.batchId);
  });
}
