import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../config/env.dart';
import '../storage/secure_store.dart';
import 'auth_backend.dart';

/// Supabase session persisted in secure storage instead of shared preferences (Section 10.2).
class SecureSessionStorage extends sb.LocalStorage {
  const SecureSessionStorage(this.store);
  final SecureStore store;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => (await store.read(SecureKeys.supabaseSession)) != null;

  @override
  Future<String?> accessToken() => store.read(SecureKeys.supabaseSession);

  @override
  Future<void> removePersistedSession() => store.delete(SecureKeys.supabaseSession);

  @override
  Future<void> persistSession(String persistSessionString) => store.write(SecureKeys.supabaseSession, persistSessionString);
}

/// [AuthBackend] on `supabase_flutter` (auth only, Section 10.1). Auto refresh is on; the session
/// survives app restarts through [SecureSessionStorage].
class SupabaseAuthBackend implements AuthBackend {
  SupabaseAuthBackend._(this._auth);

  final sb.GoTrueClient _auth;
  bool _googleReady = false;

  static Future<SupabaseAuthBackend> init(SecureStore store) async {
    if (!Env.supabaseConfigured) throw const AuthFailure(AuthFailureCode.notConfigured, 'SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY not set');
    await sb.Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabasePublishableKey,
      authOptions: sb.FlutterAuthClientOptions(localStorage: SecureSessionStorage(store), autoRefreshToken: true, authFlowType: sb.AuthFlowType.pkce),
    );
    return SupabaseAuthBackend._(sb.Supabase.instance.client.auth);
  }

  @override
  bool get hasSession => _auth.currentSession != null;

  @override
  String? get accessToken => _auth.currentSession?.accessToken;

  @override
  AuthIdentity? get identity {
    final u = _auth.currentUser;
    if (u == null) return null;
    final provider = u.appMetadata['provider'] as String? ?? (u.email != null ? 'email' : 'phone');
    return AuthIdentity(email: u.email, phone: u.phone, emailConfirmed: u.emailConfirmedAt != null || provider == 'google', provider: provider);
  }

  @override
  Stream<void> get changes => _auth.onAuthStateChange.map((_) {});

  @override
  Future<String?> refresh() async {
    try {
      return (await _auth.refreshSession()).session?.accessToken;
    } on sb.AuthException {
      return null;
    }
  }

  Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on sb.AuthException catch (e) {
      throw AuthFailure(mapAuthError(e.code, e.statusCode, e.message), e.message);
    } on AuthFailure {
      rethrow;
    } catch (e) {
      throw AuthFailure(AuthFailureCode.network, '$e');
    }
  }

  @override
  Future<void> sendPhoneOtp(String e164Phone) => _guard(() => _auth.signInWithOtp(phone: e164Phone, shouldCreateUser: false));

  @override
  Future<void> verifyPhoneOtp(String e164Phone, String code) => _guard(() => _auth.verifyOTP(phone: e164Phone, token: code, type: sb.OtpType.sms));

  @override
  Future<void> signInWithEmail(String email, String password) => _guard(() => _auth.signInWithPassword(email: email, password: password));

  /// Android: native Google sign-in → ID token → Supabase (Section 10.2). Web: OAuth redirect back to
  /// the console. Needs GOOGLE_WEB_CLIENT_ID and the Android OAuth clients (debug + release SHA-1).
  @override
  Future<void> signInWithGoogle() => _guard(() async {
        if (kIsWeb) {
          await _auth.signInWithOAuth(sb.OAuthProvider.google, redirectTo: Uri.base.origin + Uri.base.path);
          return;
        }
        if (Env.googleWebClientId.isEmpty) throw const AuthFailure(AuthFailureCode.notConfigured, 'GOOGLE_WEB_CLIENT_ID not set');
        final google = GoogleSignIn.instance;
        if (!_googleReady) {
          await google.initialize(serverClientId: Env.googleWebClientId);
          _googleReady = true;
        }
        final GoogleSignInAccount account;
        try {
          account = await google.authenticate();
        } on GoogleSignInException catch (e) {
          throw AuthFailure(e.code == GoogleSignInExceptionCode.canceled ? AuthFailureCode.cancelled : AuthFailureCode.unknown, e.description ?? '${e.code}');
        }
        final idToken = account.authentication.idToken;
        if (idToken == null) throw const AuthFailure(AuthFailureCode.unknown, 'Google returned no ID token');
        await _auth.signInWithIdToken(provider: sb.OAuthProvider.google, idToken: idToken);
      });

  @override
  Future<void> sendPasswordReset(String email) => _guard(() => _auth.resetPasswordForEmail(email, redirectTo: kIsWeb ? Uri.base.origin + Uri.base.path : Env.managerAuthCallback));

  @override
  Future<void> resendEmailConfirmation(String email) => _guard(() => _auth.resend(type: sb.OtpType.signup, email: email));

  @override
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {
      // Local sign-out still happens even if the network call fails.
    }
    if (!kIsWeb && _googleReady) await GoogleSignIn.instance.signOut().catchError((_) {});
  }
}

/// Supabase error codes (gotrue `error_code`) → what the UI shows.
@visibleForTesting
AuthFailureCode mapAuthError(String? code, String? status, String message) {
  switch (code) {
    case 'invalid_credentials':
      return AuthFailureCode.invalidCredentials;
    case 'email_not_confirmed':
      return AuthFailureCode.emailNotConfirmed;
    case 'otp_expired':
      return AuthFailureCode.otpExpired;
    case 'over_request_rate_limit':
    case 'over_sms_send_rate_limit':
    case 'over_email_send_rate_limit':
      return AuthFailureCode.rateLimited;
    case 'otp_disabled':
    case 'signup_disabled':
    case 'user_not_found':
      // Public sign-up is off (D-23): an unknown phone/email cannot get a code.
      return AuthFailureCode.signUpDisabled;
  }
  if (status == '429') return AuthFailureCode.rateLimited;
  if (message.toLowerCase().contains('token has expired or is invalid')) return AuthFailureCode.otpInvalid;
  return AuthFailureCode.unknown;
}
