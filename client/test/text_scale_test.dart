import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:iccms/core/auth/session.dart';
import 'package:iccms/core/config/app_flavor.dart';
import 'package:iccms/core/errors/app_exception.dart';
import 'package:iccms/core/providers.dart';
import 'package:iccms/core/storage/database.dart';
import 'package:iccms/core/sync/outbox_repository.dart';
import 'package:iccms/shared/screens/app_screens.dart';
import 'package:iccms/shared/screens/auth_screens.dart';
import 'package:iccms/shared/widgets/async_view.dart';
import 'package:iccms/shared/widgets/status.dart';
import 'package:iccms/core/theme/app_colors.dart';

import 'helpers.dart';

/// Section 10.2 accessibility: every shared screen at text scale 2.0 on a small phone (360×640 dp),
/// in English, Hindi and Marathi, light and dark, without overflow (overflow fails a widget test).
void main() {
  const phone = Size(360, 640);

  Future<void> pumpScreen(WidgetTester tester, Widget screen, {required AppFlavor flavor, required Locale locale, Brightness brightness = Brightness.light, List<Override> extra = const []}) async {
    tester.view.physicalSize = phone * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final backend = FakeAuthBackend()..session = true;
    final adapter = FakeAdapter((m, p, o) => p == '/me' ? (200, meJson(flavor.allowedRoles.first)) : (200, {}));
    final c = ProviderContainer(overrides: [...overridesFor(flavor, backend: backend, adapter: adapter).cast<Override>(), ...extra]);
    addTearDown(c.dispose);
    await c.read(localeProvider.notifier).set(locale.languageCode);
    await tester.pumpWidget(UncontrolledProviderScope(container: c, child: harness(screen, flavor: flavor, textScale: 2.0, locale: locale, brightness: brightness)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
  }

  for (final locale in const [Locale('en'), Locale('hi'), Locale('mr')]) {
    group('text scale 2.0 · ${locale.languageCode}', () {
      testWidgets('phone login (driver/operator)', (t) async {
        await pumpScreen(t, const PhoneLoginScreen(), flavor: AppFlavor.driver, locale: locale);
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('send-code')), findsOneWidget);
      });

      testWidgets('OTP with an error', (t) async {
        await pumpScreen(t, const OtpScreen(phone: '+919876543210'), flavor: AppFlavor.operator, locale: locale);
        await t.ensureVisible(find.byKey(const Key('verify')));
        await t.tap(find.byKey(const Key('verify')));
        await t.pump();
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('otp-error')), findsOneWidget);
      });

      testWidgets('manager login (Google + email + password)', (t) async {
        await pumpScreen(t, const ManagerLoginScreen(), flavor: AppFlavor.manager, locale: locale, brightness: Brightness.dark);
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('google')), findsOneWidget);
      });

      testWidgets('verify email', (t) async {
        await pumpScreen(t, const VerifyEmailScreen(email: 'very.long.manager.name@cold-chain.example.in'), flavor: AppFlavor.manager, locale: locale);
        expect(t.takeException(), isNull);
      });

      testWidgets('settings with pending changes', (t) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        await OutboxRepository(db).enqueue(type: 'TRIP_EVENT', entityId: 't1', payload: {'tripId': 't1'});
        await pumpScreen(t, const SettingsScreen(), flavor: AppFlavor.driver, locale: locale, extra: [databaseProvider.overrideWithValue(db), syncSchedulerProvider.overrideWithValue(null)]);
        expect(t.takeException(), isNull);
        await t.scrollUntilVisible(find.byKey(const Key('sign-out')), 200);
        expect(find.byKey(const Key('sign-out')), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('sync queue with an op needing attention and one waiting', (t) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final outbox = OutboxRepository(db);
        final bad = await outbox.enqueue(type: 'BATCH_UPDATE', entityId: 'b1', payload: {'code': 'FSH-20261114-DCK-PTN-0001'});
        await outbox.enqueue(type: 'POD', entityId: 's1', payload: {'tripId': 'TRP-20261114-0001'});
        await db.customStatement("UPDATE outbox_ops SET status = 'attention', last_error_code = 'EDIT_WINDOW_CLOSED', last_error = 'The 30-minute edit window has closed; request an edit' WHERE client_op_id = '$bad'");
        await pumpScreen(t, const SyncQueueScreen(), flavor: AppFlavor.operator, locale: locale, extra: [databaseProvider.overrideWithValue(db), syncSchedulerProvider.overrideWithValue(null)]);
        await t.pump(const Duration(milliseconds: 300));
        expect(t.takeException(), isNull);
        expect(find.textContaining('EDIT_WINDOW_CLOSED'), findsOneWidget);
      });

      testWidgets('flavor home, update-required, async error / empty, status chips', (t) async {
        await pumpScreen(
          t,
          Builder(builder: (context) => const FlavorHomeScreen(moduleTag: 'iccms-module-driver')),
          flavor: AppFlavor.driver,
          locale: locale,
          extra: [sessionProvider.overrideWith(() => _SignedInController())],
        );
        expect(t.takeException(), isNull);
        for (final w in <Widget>[
          const UpdateRequiredScreen(),
          Scaffold(body: AsyncView<int>(value: const AsyncValue.error(AppException('X', 'Server message that is quite long and wraps', status: 500), StackTrace.empty), data: (_) => const SizedBox(), onRetry: () {})),
          Scaffold(body: AsyncView<List<int>>(value: const AsyncValue.data([]), isEmpty: (l) => l.isEmpty, data: (_) => const SizedBox())),
          const Scaffold(body: Wrap(children: [StatusChip(level: StatusLevel.critical), GradeChip(grade: 'B'), StatusChip(level: StatusLevel.safe)])),
          const Scaffold(body: SkeletonList()),
        ]) {
          await pumpScreen(t, w, flavor: AppFlavor.driver, locale: locale);
          expect(t.takeException(), isNull, reason: '$w');
        }
      });
    });
  }
}

class _SignedInController extends SessionController {
  @override
  SessionState build() => const SignedIn(Me(id: 'u', name: 'Ravindra Shankar Deshmukh', role: 'DRIVER', emailVerified: false, language: 'en', siteName: 'Chhatrapati Sambhajinagar Distribution Centre'));
}
