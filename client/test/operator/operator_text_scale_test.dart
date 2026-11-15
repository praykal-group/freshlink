import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:iccms/apps/operator/data/operator_repository.dart';
import 'package:iccms/apps/operator/providers.dart';
import 'package:iccms/apps/operator/screens/batches_screens.dart';
import 'package:iccms/apps/operator/screens/home_screen.dart';
import 'package:iccms/apps/operator/screens/receive_load_screens.dart';
import 'package:iccms/apps/operator/screens/wizard_screen.dart';
import 'package:iccms/core/config/app_flavor.dart';
import 'package:iccms/core/providers.dart';
import 'package:iccms/core/storage/database.dart';
import 'package:iccms/core/tags/tag_reader.dart';

import '../helpers.dart';
import 'fake_server.dart';

/// M11: operator screens at text scale 2.0 on a 360×640 dp phone in EN / HI / MR (Hindi + Marathi
/// checked for overflow). An overflow fails the test.
class _Reader implements TagReader {
  const _Reader(this.kind, this.uid);
  @override
  final TagKind kind;
  final String uid;
  @override
  Future<TagRead?> read(BuildContext context) async => TagRead(kind, uid);
}

void main() {
  Future<void> pump(WidgetTester t, Widget screen, Locale locale, {Future<void> Function(AppDatabase db)? seed}) async {
    t.view.physicalSize = const Size(1080, 1920);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final server = FakeIccmsServer();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final c = ProviderContainer(overrides: [
      ...overridesFor(AppFlavor.operator, backend: FakeAuthBackend()..session = true, adapter: server.adapter).cast<Override>(),
      databaseProvider.overrideWithValue(db),
      syncSchedulerProvider.overrideWithValue(null),
      tagReadersProvider.overrideWithValue(const {
        TagKind.nfc: _Reader(TagKind.nfc, '04A1B2C3D4'),
        TagKind.qr: _Reader(TagKind.qr, 'FSH-20261115-DCK-PTN-9999'),
        TagKind.uhf: _Reader(TagKind.uhf, 'E2003412'),
      }),
    ]);
    addTearDown(c.dispose);
    if (seed != null) await t.runAsync(() => seed(db));
    await t.runAsync(() => c.read(localeProvider.notifier).set(locale.languageCode));
    await t.pumpWidget(UncontrolledProviderScope(container: c, child: harness(screen, flavor: AppFlavor.operator, textScale: 2.0, locale: locale)));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  for (final locale in const [Locale('en'), Locale('hi'), Locale('mr')]) {
    group('operator · text scale 2.0 · ${locale.languageCode}', () {
      testWidgets('home with a draft to resume', (t) async {
        await pump(t, const OperatorHomeScreen(), locale, seed: (db) => db.saveDraft(WizardDraft(category: 'FISH', step: 2, batchId: 'b-1')));
        expect(t.takeException(), isNull);
        await t.scrollUntilVisible(find.byKey(const Key('new-fish')), 200);
        expect(find.byKey(const Key('new-fish')), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('new fish batch: details form', (t) async {
        await pump(t, const BatchWizardScreen(category: 'FISH'), locale);
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('product-ROHU')), findsOneWidget);
      });

      testWidgets('new produce batch: details form', (t) async {
        await pump(t, const BatchWizardScreen(category: 'PRODUCE'), locale);
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('product-BANANA')), findsOneWidget);
      });

      for (final step in [1, 2, 3, 4, 5, 6]) {
        testWidgets('wizard step ${step + 1} (resumed)', (t) async {
          await pump(t, const BatchWizardScreen(category: 'FISH', resume: true), locale, seed: (db) async {
            await db.into(db.cachedMasters).insert(CachedMastersCompanion.insert(kind: 'bundle', payload: '{"products":[{"id":"p-rohu","code":"ROHU","name":"Rohu","nameHi":"रोहू","nameMr":"रोहू","category":"FISH","isClimacteric":false,"safeTempMin":"0","safeTempMax":"4"}],"sites":[],"storageUnits":[]}', updatedAt: DateTime.now()));
            await db.saveDraft(WizardDraft(
              category: 'FISH', step: step, batchId: 'b-1', startedAt: DateTime.now(), grade: step >= 4 ? 'B' : null, gradeQueued: step >= 3,
              form: {'productId': 'p-rohu', 'weightKg': '120', 'photo.TOP': {'size': 380000, 'w': 1280, 'h': 960}},
              photos: {'TOP': 'missing/top.jpg'},
            ));
          });
          await t.pump(const Duration(milliseconds: 500));
          expect(t.takeException(), isNull);
        });
      }

      testWidgets('receive: scan', (t) async {
        await pump(t, const ReceiveScreen(), locale);
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('tag-nfc')), findsOneWidget);
      });

      testWidgets('load truck: trip list, then a trip with a wrong-batch warning', (t) async {
        await pump(t, const LoadTruckScreen(), locale);
        expect(t.takeException(), isNull);
        await t.tap(find.text('TRP-20261115-0001'));
        await t.pump(const Duration(milliseconds: 300));
        await t.scrollUntilVisible(find.byKey(const Key('tag-qr')), 200);
        await t.ensureVisible(find.byKey(const Key('tag-qr'))); // to the top: the pinned button grows at 2.0
        await t.pump();
        await t.tap(find.byKey(const Key('tag-qr')));
        await t.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const Key('load-warning'), skipOffstage: false), findsOneWidget, reason: 'a batch not allocated to the trip is flagged');
        expect(t.takeException(), isNull);
      });

      testWidgets('batch list with a not-yet-synced batch', (t) async {
        await pump(t, const BatchListScreen(), locale);
        expect(t.takeException(), isNull);
      });
    });
  }
}
