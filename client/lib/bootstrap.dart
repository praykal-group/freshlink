import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import 'core/auth/auth_backend.dart';
import 'core/auth/supabase_auth_backend.dart';
import 'core/config/app_flavor.dart';
import 'core/l10n/l10n.dart';
import 'core/providers.dart';
import 'core/push/push_service.dart';
import 'core/router/app_router.dart';
import 'core/storage/database.dart';
import 'core/storage/db_connection.dart';
import 'core/storage/db_key.dart';
import 'core/storage/secure_store.dart';
import 'core/theme/app_theme.dart';

/// Shared start-up for every flavor (Section 10.2): secure storage, device id, Supabase, the
/// encrypted DB + outbox sync (driver/operator), push, then the app.
Future<void> bootstrap(AppFlavorConfig config) async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = FlutterSecureStore();
  final deviceId = await _deviceId(store);
  final version = await _version();

  AuthBackend backend;
  try {
    backend = await SupabaseAuthBackend.init(store);
  } on AuthFailure catch (e) {
    debugPrint('auth: $e');
    backend = const UnconfiguredAuthBackend();
  }

  final push = PushService(config.flavor);
  await push.init().catchError((Object e) => debugPrint('push init failed: $e'));

  AppDatabase? db;
  if (config.flavor.hasOfflineOutbox && !kIsWeb) db = AppDatabase(openEncryptedDatabase(await loadOrCreateDbKey(store)));

  final container = ProviderContainer(overrides: [
    flavorConfigProvider.overrideWithValue(config),
    secureStoreProvider.overrideWithValue(store),
    authBackendProvider.overrideWithValue(backend),
    deviceIdProvider.overrideWithValue(deviceId),
    appVersionProvider.overrideWithValue(version),
    pushServiceProvider.overrideWithValue(push),
    databaseProvider.overrideWithValue(db),
  ]);
  container.read(syncSchedulerProvider); // starts outbox sync (driver/operator)
  runApp(UncontrolledProviderScope(container: container, child: const IccmsApp()));
}

Future<String> _deviceId(SecureStore store) async {
  final existing = await store.read(SecureKeys.deviceId);
  if (existing != null) return existing;
  String id = const Uuid().v4();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      id = '${info.model.replaceAll(RegExp(r'[^A-Za-z0-9]'), '')}-$id';
    } catch (_) {}
  }
  await store.write(SecureKeys.deviceId, id);
  return id;
}

Future<AppVersion> _version() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return AppVersion(info.version, int.tryParse(info.buildNumber) ?? 1);
  } catch (_) {
    return const AppVersion('0.0.0', 1);
  }
}

class IccmsApp extends ConsumerWidget {
  const IccmsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(flavorConfigProvider);
    // Wires 426 / revoked-session events from every API call to the router and session.
    ref.watch(upgradeRequiredProvider);
    return MaterialApp.router(
      title: config.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(config.flavor, Brightness.light),
      darkTheme: AppTheme.build(config.flavor, Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      locale: ref.watch(localeProvider),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      routerConfig: ref.watch(routerProvider),
    );
  }
}
