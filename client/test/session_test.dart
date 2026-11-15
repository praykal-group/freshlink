import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iccms/apps/driver/router.dart';
import 'package:iccms/apps/manager/router.dart';
import 'package:iccms/apps/operator/router.dart';
import 'package:iccms/bootstrap.dart';
import 'package:iccms/core/auth/auth_backend.dart';
import 'package:iccms/core/auth/session.dart';
import 'package:iccms/core/config/app_flavor.dart';
import 'package:iccms/core/providers.dart';
import 'package:iccms/core/storage/database.dart';
import 'package:iccms/core/router/app_router.dart';
import 'package:iccms/core/storage/secure_store.dart';

import 'helpers.dart';

ProviderContainer containerFor(AppFlavor f, FakeAuthBackend backend, FakeAdapter adapter, {SecureStore? store}) {
  final c = ProviderContainer(overrides: [...overridesFor(f, backend: backend, adapter: adapter, store: store)].cast());
  addTearDown(c.dispose);
  return c;
}

Future<SessionState> settle(ProviderContainer c) async {
  c.read(sessionProvider);
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (c.read(sessionProvider) is! SessionUnknown) break;
  }
  return c.read(sessionProvider);
}

void main() {
  group('session (Section 10.2 core/auth)', () {
    test('sign-in → POST /me/session {deviceId, appVersionCode} → GET /me → SignedIn', () async {
      final backend = FakeAuthBackend();
      final adapter = FakeAdapter((m, p, o) => switch (p) {
            '/me/session' => (200, {'ok': true}),
            '/me' => (200, meJson('DRIVER')),
            _ => (404, envelope('NOT_FOUND')),
          });
      final c = containerFor(AppFlavor.driver, backend, adapter);
      expect(await settle(c), isA<SignedOut>());
      await backend.verifyPhoneOtp('+919876543210', '123456');
      await c.read(sessionProvider.notifier).completeSignIn();
      final s = c.read(sessionProvider);
      expect(s, isA<SignedIn>());
      expect((s as SignedIn).me.role, 'DRIVER');
      final session = adapter.requests.firstWhere((r) => r.path.endsWith('/me/session'));
      expect(session.data, {'deviceId': 'test-device-1', 'appVersionCode': 7});
      expect(session.headers['X-App-Flavor'], 'driver');
    });

    test('wrong-role login (server 403 WRONG_APP_FOR_ROLE) → signed out with a clear reason', () async {
      final backend = FakeAuthBackend()..session = true;
      final adapter = FakeAdapter((m, p, o) => (403, envelope('WRONG_APP_FOR_ROLE', 'This account cannot use the driver app')));
      final c = containerFor(AppFlavor.driver, backend, adapter);
      final s = await settle(c);
      expect(s, isA<SignedOut>().having((x) => x.reason, 'reason', 'WRONG_APP_FOR_ROLE'));
      expect(backend.signOuts, 1);
      expect(backend.hasSession, isFalse);
    });

    test('a role this app does not allow is refused even if the server answered /me', () async {
      final backend = FakeAuthBackend()..session = true;
      final adapter = FakeAdapter((m, p, o) => p == '/me' ? (200, meJson('MANAGER')) : (200, {}));
      final c = containerFor(AppFlavor.operator, backend, adapter);
      expect(await settle(c), isA<SignedOut>().having((x) => x.reason, 'reason', 'WRONG_APP_FOR_ROLE'));
      expect(backend.signOuts, 1);
    });

    test('NOT_REGISTERED / SESSION_ON_OTHER_DEVICE also sign out with their reason', () async {
      for (final code in ['NOT_REGISTERED', 'SESSION_ON_OTHER_DEVICE']) {
        final backend = FakeAuthBackend()..session = true;
        final adapter = FakeAdapter((m, p, o) => (code == 'NOT_REGISTERED' ? 403 : 409, envelope(code)));
        final c = containerFor(AppFlavor.driver, backend, adapter);
        expect(await settle(c), isA<SignedOut>().having((x) => x.reason, 'reason', code));
      }
    });

    test('session survives an app restart offline: cached profile for driver/operator, not for manager', () async {
      final store = MemorySecureStore();
      var online = true;
      final adapter = FakeAdapter((m, p, o) => !online ? (0, null) : (p == '/me' ? (200, meJson('OPERATOR')) : (200, {})));
      final first = containerFor(AppFlavor.operator, FakeAuthBackend()..session = true, adapter, store: store);
      expect(await settle(first), isA<SignedIn>());

      online = false; // "restart" in airplane mode
      final second = containerFor(AppFlavor.operator, FakeAuthBackend()..session = true, adapter, store: store);
      final s = await settle(second);
      expect(s, isA<SignedIn>().having((x) => x.offline, 'offline', isTrue));
      expect((s as SignedIn).me.role, 'OPERATOR');

      final managerStore = MemorySecureStore()..values['iccms.me'] = '{"id":"u","name":"M","role":"MANAGER","emailVerified":true,"language":"EN"}';
      final mgr = containerFor(AppFlavor.manager, FakeAuthBackend()..session = true, adapter, store: managerStore);
      expect(await settle(mgr), isA<SignedOut>(), reason: 'manager app is online-only');
    });

    test('manager with an unconfirmed email → NeedsEmailVerification (no API call)', () async {
      final backend = FakeAuthBackend()
        ..session = true
        ..id = const AuthIdentity(email: 'm@iccms.in', emailConfirmed: false, provider: 'email');
      final adapter = FakeAdapter((m, p, o) => (200, meJson('MANAGER')));
      final c = containerFor(AppFlavor.manager, backend, adapter);
      expect(await settle(c), isA<NeedsEmailVerification>().having((x) => x.email, 'email', 'm@iccms.in'));
      expect(adapter.requests, isEmpty);
    });

    test('a 401 mid-session refreshes the token once (single flight) and the call succeeds', () async {
      final backend = FakeAuthBackend()..session = true;
      final adapter = FakeAdapter((m, p, o) => o.headers['Authorization'] == 'Bearer access-1' ? (401, envelope('UNAUTHORIZED')) : (p == '/me' ? (200, meJson('DRIVER')) : (200, {})));
      final c = containerFor(AppFlavor.driver, backend, adapter);
      expect(await settle(c), isA<SignedIn>());
      expect(backend.refreshes, 1);
    });

    test('a revoked session during use (409 on any call) signs out', () async {
      final backend = FakeAuthBackend()..session = true;
      var revoked = false;
      final adapter = FakeAdapter((m, p, o) => revoked ? (409, envelope('SESSION_ON_OTHER_DEVICE')) : (p == '/me' ? (200, meJson('DRIVER')) : (200, {})));
      final c = containerFor(AppFlavor.driver, backend, adapter);
      c.listen(upgradeRequiredProvider, (_, _) {});
      expect(await settle(c), isA<SignedIn>());
      revoked = true;
      await c.read(apiClientProvider).get('/driver/trips/current').catchError((_) => null);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.read(sessionProvider), isA<SignedOut>().having((x) => x.reason, 'reason', 'SESSION_ON_OTHER_DEVICE'));
    });
  });

  group('wrong-role login through the UI', () {
    testWidgets('driver app: OTP ok but the account is an OPERATOR → login screen with the reason, signed out', (tester) async {
      final backend = FakeAuthBackend();
      final adapter = FakeAdapter((m, p, o) => (403, envelope('WRONG_APP_FOR_ROLE')));
      final c = ProviderContainer(overrides: [...overridesFor(AppFlavor.driver, backend: backend, adapter: adapter, router: const DriverRouter())].cast());
      addTearDown(c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const IccmsApp()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('phone')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('phone')), '9876543210');
      await tester.tap(find.byKey(const Key('send-code')));
      await tester.pumpAndSettle();
      expect(backend.calls, contains('sendPhoneOtp +919876543210'));
      await tester.enterText(find.byKey(const Key('otp')), '123456');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('signout-reason')), findsOneWidget);
      expect(find.text('Your account cannot use this app. Please use the app for your role.'), findsOneWidget);
      expect(backend.signOuts, 1);
      expect(find.byKey(const Key('module-tag')), findsNothing);
    });
  });

  group('each flavor lands on its own home with its own module tag', () {
    final cases = <AppFlavor, (FlavorRouter, String)>{
      AppFlavor.driver: (const DriverRouter(), 'DRIVER'),
      AppFlavor.operator: (const OperatorRouter(), 'OPERATOR'),
      AppFlavor.manager: (const ManagerRouter(), 'MANAGER'),
    };
    cases.forEach((flavor, v) {
      testWidgets(flavor.name, (tester) async {
        final backend = FakeAuthBackend()
          ..session = true
          ..id = const AuthIdentity(email: 'x@iccms.in', emailConfirmed: true, provider: 'google');
        final adapter = FakeAdapter((m, p, o) => p == '/me' ? (200, meJson(v.$2, name: 'Asha')) : (200, {}));
        // The operator app works on its local database (outbox, cached masters).
        final db = flavor == AppFlavor.operator ? AppDatabase(NativeDatabase.memory()) : null;
        if (db != null) addTearDown(db.close);
        final c = ProviderContainer(overrides: [
          ...overridesFor(flavor, backend: backend, adapter: adapter, router: v.$1),
          if (db != null) databaseProvider.overrideWithValue(db),
          if (db != null) syncSchedulerProvider.overrideWithValue(null),
        ].cast());
        addTearDown(c.dispose);
        await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const IccmsApp()));
        await tester.pumpAndSettle();
        // The operator home lists its actions first; the module tag is at the end of the list.
        await tester.scrollUntilVisible(find.text('iccms-module-${flavor.name}'), 300);
        expect(find.text('iccms-module-${flavor.name}'), findsOneWidget);
        expect(find.text('Hello, Asha'), findsOneWidget);
        expect(c.read(routerProvider).routerDelegate.currentConfiguration.uri.path, '/home');
        unawaited(c.read(routerProvider).push('/settings'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('sign-out')), findsOneWidget);
      });
    });
  });
}
