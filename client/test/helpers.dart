import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:iccms/core/auth/auth_backend.dart';
import 'package:iccms/core/config/app_flavor.dart';
import 'package:iccms/core/l10n/l10n.dart';
import 'package:iccms/core/providers.dart';
import 'package:iccms/core/storage/secure_store.dart';
import 'package:iccms/core/theme/app_theme.dart';

/// A scripted HTTP server for ApiClient: `handler(method, path, request)` returns (status, json).
typedef Handler = FutureOr<(int, Object?)> Function(String method, String path, RequestOptions o);

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);
  final Handler handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(o);
    final (status, body) = await handler(o.method, o.uri.path.replaceFirst('/api/v1', ''), o);
    if (status == 0) throw DioException.connectionError(requestOptions: o, reason: 'offline');
    return ResponseBody.fromString(body == null ? '' : jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> envelope(String code, [String message = 'error']) => {'error': {'code': code, 'message': message, 'details': {}}};

Map<String, dynamic> meJson(String role, {String name = 'Ravi'}) => {
      'id': 'u-1', 'name': name, 'role': role, 'phone': '+919999900011', 'email': null, 'emailVerified': false, 'language': 'EN',
      'site': {'id': 's-1', 'code': 'DCK-PTN', 'name': 'Paithan Dock', 'type': 'DOCK'}, 'flags': {},
    };

class FakeAuthBackend implements AuthBackend {
  bool session = false;
  String? token = 'access-1';
  AuthIdentity? id;
  int signOuts = 0;
  int refreshes = 0;
  AuthFailure? failNext;
  final List<String> calls = [];
  final _changes = StreamController<void>.broadcast();

  @override
  bool get hasSession => session;
  @override
  String? get accessToken => session ? token : null;
  @override
  AuthIdentity? get identity => id;
  @override
  Stream<void> get changes => _changes.stream;

  Future<void> _maybeFail(String call) async {
    calls.add(call);
    final f = failNext;
    failNext = null;
    if (f != null) throw f;
  }

  @override
  Future<String?> refresh() async {
    refreshes++;
    token = 'access-${refreshes + 1}';
    return token;
  }

  @override
  Future<void> sendPhoneOtp(String e164Phone) => _maybeFail('sendPhoneOtp $e164Phone');
  @override
  Future<void> verifyPhoneOtp(String e164Phone, String code) async {
    await _maybeFail('verifyPhoneOtp $e164Phone $code');
    session = true;
    id = AuthIdentity(phone: e164Phone, emailConfirmed: false, provider: 'phone');
  }

  @override
  Future<void> signInWithEmail(String email, String password) async {
    await _maybeFail('signInWithEmail $email');
    session = true;
    id ??= AuthIdentity(email: email, emailConfirmed: true, provider: 'email');
  }

  @override
  Future<void> signInWithGoogle() async {
    await _maybeFail('signInWithGoogle');
    session = true;
    id = const AuthIdentity(email: 'm@x.in', emailConfirmed: true, provider: 'google');
  }

  @override
  Future<void> sendPasswordReset(String email) => _maybeFail('sendPasswordReset $email');
  @override
  Future<void> resendEmailConfirmation(String email) => _maybeFail('resend $email');
  @override
  Future<void> signOut() async {
    signOuts++;
    session = false;
    id = null;
  }
}

class _DummyRouter extends FlavorRouter {
  const _DummyRouter();
  @override
  String get homePath => '/home';
  @override
  List<Never> get routes => const [];
}

AppFlavorConfig configFor(AppFlavor f, {FlavorRouter router = const _DummyRouter()}) => AppFlavorConfig(flavor: f, appName: 'I-CCMS ${f.name}', router: router);

/// Overrides for a test container: fake auth + scripted API.
List overridesFor(AppFlavor f, {required FakeAuthBackend backend, required FakeAdapter adapter, SecureStore? store, FlavorRouter? router}) => [
      flavorConfigProvider.overrideWithValue(router == null ? configFor(f) : configFor(f, router: router)),
      secureStoreProvider.overrideWithValue(store ?? MemorySecureStore()),
      authBackendProvider.overrideWithValue(backend),
      deviceIdProvider.overrideWithValue('test-device-1'),
      appVersionProvider.overrideWithValue(const AppVersion('1.0.0', 7)),
      apiClientAdapterProvider.overrideWithValue(adapter),
    ];

/// A screen inside the app theme + localisation at a given text scale and locale.
Widget harness(Widget child, {AppFlavor flavor = AppFlavor.driver, double textScale = 1.0, Locale locale = const Locale('en'), Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: AppTheme.build(flavor, brightness),
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [AppLocalizations.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
    builder: (context, w) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: w!),
    home: child,
  );
}
