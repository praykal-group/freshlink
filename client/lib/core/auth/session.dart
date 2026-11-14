import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_flavor.dart';
import '../errors/app_exception.dart';
import '../network/api_client.dart';
import '../providers.dart';
import '../storage/secure_store.dart';
import 'auth_backend.dart';

/// `GET /me` (backend AuthService.me).
class Me {
  const Me({required this.id, required this.name, required this.role, this.phone, this.email, required this.emailVerified, required this.language, this.siteName, this.siteCode, this.flags = const {}});

  factory Me.fromJson(Map<String, dynamic> j) => Me(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        role: j['role'] as String,
        phone: j['phone'] as String?,
        email: j['email'] as String?,
        emailVerified: j['emailVerified'] == true,
        language: (j['language'] as String? ?? 'EN').toLowerCase(),
        siteName: (j['site'] as Map?)?['name'] as String?,
        siteCode: (j['site'] as Map?)?['code'] as String?,
        flags: Map<String, dynamic>.from((j['flags'] as Map?) ?? const {}),
      );

  final String id;
  final String name;
  final String role;
  final String? phone;
  final String? email;
  final bool emailVerified;
  final String language;
  final String? siteName;
  final String? siteCode;
  final Map<String, dynamic> flags;

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'role': role, 'phone': phone, 'email': email, 'emailVerified': emailVerified, 'language': language.toUpperCase(),
        'site': siteName == null ? null : {'name': siteName, 'code': siteCode}, 'flags': flags,
      };
}

sealed class SessionState {
  const SessionState();
}

/// Restoring the stored session (splash).
class SessionUnknown extends SessionState {
  const SessionUnknown();
}

class SignedOut extends SessionState {
  const SignedOut({this.reason});

  /// Why the user was signed out: an AppException code (WRONG_APP_FOR_ROLE, NOT_REGISTERED,
  /// SESSION_ON_OTHER_DEVICE) shown once on the login screen.
  final String? reason;
}

/// Manager email login before the address is confirmed (AUTH-03): "Check your inbox".
class NeedsEmailVerification extends SessionState {
  const NeedsEmailVerification(this.email);
  final String email;
}

class SignedIn extends SessionState {
  const SignedIn(this.me, {this.offline = false});
  final Me me;

  /// Started without network with the cached profile (driver/operator keep working offline).
  final bool offline;
}

/// The backend calls the session needs.
class SessionApi {
  SessionApi(this.api);
  final ApiClient api;

  Future<void> registerSession({required String deviceId, required int appVersionCode, String? fcmToken}) =>
      api.post('/me/session', body: {'deviceId': deviceId, 'appVersionCode': appVersionCode, 'fcmToken': ?fcmToken});

  Future<Me> me() async => Me.fromJson(Map<String, dynamic>.from(await api.get('/me') as Map));

  Future<void> logout() => api.post('/me/logout');
}

const _meKey = 'iccms.me';

/// Session lifecycle (Section 10.2 core/auth): after every sign-in `POST /me/session` → `GET /me`.
/// A 403 WRONG_APP_FOR_ROLE / NOT_REGISTERED (or a role this app does not allow) signs the user
/// out with a clear message. Without network a previously signed-in driver/operator keeps working
/// on the cached profile. Dependencies come from providers (overridden in bootstrap and tests).
class SessionController extends Notifier<SessionState> {
  late AppFlavor flavor;
  late AuthBackend backend;
  late SessionApi sessionApi;
  late SecureStore store;
  late String deviceId;
  late int versionCode;
  Future<String?> Function()? fcmToken;
  StreamSubscription<void>? _changes;

  @override
  SessionState build() {
    flavor = ref.read(flavorProvider);
    backend = ref.read(authBackendProvider);
    sessionApi = SessionApi(ref.read(apiClientProvider));
    store = ref.read(secureStoreProvider);
    deviceId = ref.read(deviceIdProvider);
    versionCode = ref.read(appVersionProvider).code;
    final push = ref.read(pushServiceProvider);
    fcmToken = push?.token;
    ref.onDispose(() => _changes?.cancel());
    scheduleMicrotask(restore);
    return const SessionUnknown();
  }

  Future<void> restore() async {
    if (!backend.hasSession) {
      state = const SignedOut();
      return;
    }
    await completeSignIn();
  }

  /// After Supabase signed the user in (OTP verified, password ok, Google ok).
  Future<void> completeSignIn() async {
    final id = backend.identity;
    if (flavor == AppFlavor.manager && id != null && id.provider == 'email' && !id.emailConfirmed) {
      state = NeedsEmailVerification(id.email ?? '');
      return;
    }
    try {
      await sessionApi.registerSession(deviceId: deviceId, appVersionCode: versionCode, fcmToken: await _fcm());
      final me = await sessionApi.me();
      if (!flavor.allowedRoles.contains(me.role)) {
        await _revoke(AppException.wrongAppForRole);
        return;
      }
      await store.write(_meKey, jsonEncode(me.toJson()));
      state = SignedIn(me);
    } on AppException catch (e) {
      if (e.code == AppException.wrongAppForRole || e.code == AppException.notRegistered || e.code == AppException.sessionOnOtherDevice || e.status == 401) {
        await _revoke(e.status == 401 ? AppException.unauthorized : e.code);
        return;
      }
      // No network / server down: offline start on the cached profile (outbox flavors only).
      final cached = await store.read(_meKey);
      if (e.isTransient && cached != null && flavor.hasOfflineOutbox) {
        state = SignedIn(Me.fromJson(jsonDecode(cached) as Map<String, dynamic>), offline: true);
        return;
      }
      state = SignedOut(reason: e.code);
    }
  }

  /// The server revoked access during use (ApiClient SessionRevokedEvent).
  Future<void> onRevoked(AppException e) => _revoke(e.code);

  Future<void> _revoke(String reason) async {
    // The API client's global event and the sign-in flow can both report the same refusal.
    if (state is SignedOut && !backend.hasSession) {
      state = SignedOut(reason: reason);
      return;
    }
    await backend.signOut();
    await store.delete(_meKey);
    state = SignedOut(reason: reason);
  }

  Future<void> signOut() async {
    try {
      await sessionApi.logout();
    } catch (_) {}
    await backend.signOut();
    await store.delete(_meKey);
    state = const SignedOut();
  }

  Future<String?> _fcm() async {
    try {
      return await fcmToken?.call();
    } catch (_) {
      return null;
    }
  }
}
