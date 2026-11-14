import 'package:dio/dio.dart' show HttpClientAdapter;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_backend.dart';
import 'auth/session.dart';
import 'config/app_flavor.dart';
import 'config/env.dart';
import 'network/api_client.dart';
import 'push/push_service.dart';
import 'realtime/realtime_client.dart';
import 'storage/database.dart';
import 'storage/secure_store.dart';
import 'sync/api_sync_api.dart';
import 'sync/outbox_repository.dart';
import 'sync/sync_engine.dart';
import 'sync/sync_scheduler.dart';

/// Values created in `bootstrap()` before the widget tree exists. Every one is overridden there
/// (and in tests); reading one without an override is a programming error.
T _missing<T>(String name) => throw StateError('$name must be overridden in bootstrap()');

final flavorConfigProvider = Provider<AppFlavorConfig>((_) => _missing('flavorConfigProvider'));
final secureStoreProvider = Provider<SecureStore>((_) => _missing('secureStoreProvider'));
final authBackendProvider = Provider<AuthBackend>((_) => _missing('authBackendProvider'));
final deviceIdProvider = Provider<String>((_) => _missing('deviceIdProvider'));

class AppVersion {
  const AppVersion(this.name, this.code);
  final String name;
  final int code;
}

final appVersionProvider = Provider<AppVersion>((_) => const AppVersion('0.0.0', 1));

/// Local database: null for the manager app / web console (online-only, Section 10.6).
final databaseProvider = Provider<AppDatabase?>((_) => null);
final pushServiceProvider = Provider<PushService?>((_) => null);

final flavorProvider = Provider<AppFlavor>((ref) => ref.watch(flavorConfigProvider).flavor);

// ───────────── preferences (secure store; tiny) ─────────────

const _localeKey = 'iccms.locale';
const _themeKey = 'iccms.theme';
const supportedLanguages = ['en', 'hi', 'mr'];

class LocaleController extends Notifier<Locale> {
  @override
  Locale build() {
    ref.read(secureStoreProvider).read(_localeKey).then((v) {
      if (v != null && supportedLanguages.contains(v) && v != state.languageCode) state = Locale(v);
    });
    return const Locale('en');
  }

  Future<void> set(String languageCode) async {
    if (!supportedLanguages.contains(languageCode)) return;
    state = Locale(languageCode);
    await ref.read(secureStoreProvider).write(_localeKey, languageCode);
  }
}

final localeProvider = NotifierProvider<LocaleController, Locale>(LocaleController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    ref.read(secureStoreProvider).read(_themeKey).then((v) {
      final m = ThemeMode.values.where((t) => t.name == v).firstOrNull;
      if (m != null && m != state) state = m;
    });
    return ref.read(flavorProvider).defaultThemeMode;
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref.read(secureStoreProvider).write(_themeKey, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

// ───────────── network ─────────────

class _BackendTokens implements TokenSource {
  _BackendTokens(this.backend);
  final AuthBackend backend;

  @override
  String? get accessToken => backend.accessToken;

  @override
  Future<String?> refresh() => backend.refresh();
}

/// Tests replace the HTTP transport with a scripted fake.
final apiClientAdapterProvider = Provider<HttpClientAdapter?>((_) => null);

final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(flavorConfigProvider);
  final client = ApiClient(
    baseUrl: Env.apiBaseUrl,
    adapter: ref.watch(apiClientAdapterProvider),
    tokens: _BackendTokens(ref.watch(authBackendProvider)),
    info: ClientInfo(
      flavor: config.headerValue(isWeb: kIsWeb),
      versionCode: ref.watch(appVersionProvider).code,
      deviceId: ref.watch(deviceIdProvider),
      language: () => ref.read(localeProvider).languageCode,
    ),
  );
  ref.onDispose(client.dispose);
  return client;
});

/// True after any API call answered 426: the router shows the blocking update screen.
class UpgradeRequiredController extends Notifier<bool> {
  @override
  bool build() {
    final sub = ref.watch(apiClientProvider).events.listen((e) {
      if (e is UpgradeRequiredEvent) state = true;
      if (e is SessionRevokedEvent) ref.read(sessionProvider.notifier).onRevoked(e.error);
    });
    ref.onDispose(sub.cancel);
    return false;
  }
}

final upgradeRequiredProvider = NotifierProvider<UpgradeRequiredController, bool>(UpgradeRequiredController.new);

final sessionProvider = NotifierProvider<SessionController, SessionState>(SessionController.new);

// ───────────── offline + realtime ─────────────

/// Outbox sync for driver/operator (null for manager/web): starts with the app, stops with it.
final syncSchedulerProvider = Provider<SyncScheduler?>((ref) {
  final db = ref.watch(databaseProvider);
  if (db == null) return null;
  final scheduler = SyncScheduler(SyncEngine(db, ApiSyncApi(ref.watch(apiClientProvider))));
  scheduler.start();
  ref.onDispose(scheduler.stop);
  return scheduler;
});

final outboxProvider = Provider<OutboxRepository?>((ref) {
  final db = ref.watch(databaseProvider);
  return db == null ? null : OutboxRepository(db);
});

/// Ops not yet confirmed by the server (badge + settings + sign-out warning).
final pendingOpsProvider = StreamProvider<int>((ref) => ref.watch(outboxProvider)?.watchPendingCount() ?? Stream.value(0));

final onlineProvider = StreamProvider<bool>((ref) async* {
  final scheduler = ref.watch(syncSchedulerProvider);
  if (scheduler == null) {
    yield true;
    return;
  }
  yield scheduler.online;
  await for (final _ in scheduler.reports) {
    yield scheduler.online;
  }
});

final realtimeProvider = Provider<RealtimeClient?>((ref) {
  final session = ref.watch(sessionProvider);
  if (session is! SignedIn) return null;
  final backend = ref.watch(authBackendProvider);
  final client = RealtimeClient(url: Env.wsUrl, flavor: ref.watch(flavorConfigProvider).headerValue(isWeb: kIsWeb), token: () => backend.accessToken);
  client.connect();
  ref.onDispose(client.dispose);
  return client;
});
