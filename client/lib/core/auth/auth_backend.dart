/// Identity provider operations the app needs (Section 10.2 core/auth). Implemented by
/// [SupabaseAuthBackend]; tests use a fake. Passwords and OTPs only pass through to Supabase:
/// the app never stores or logs them (Section 14).
abstract class AuthBackend {
  /// True when a (possibly expired) session is stored; the SDK refreshes it on use.
  bool get hasSession;
  String? get accessToken;

  /// Email of the signed-in user and whether it is confirmed (manager email login, AUTH-03).
  AuthIdentity? get identity;

  Stream<void> get changes;

  Future<String?> refresh();
  Future<void> sendPhoneOtp(String e164Phone);
  Future<void> verifyPhoneOtp(String e164Phone, String code);
  Future<void> signInWithEmail(String email, String password);
  Future<void> signInWithGoogle();
  Future<void> sendPasswordReset(String email);
  Future<void> resendEmailConfirmation(String email);
  Future<void> signOut();
}

class AuthIdentity {
  const AuthIdentity({this.email, this.phone, required this.emailConfirmed, required this.provider});
  final String? email;
  final String? phone;
  final bool emailConfirmed;

  /// email | phone | google
  final String provider;
}

enum AuthFailureCode { notConfigured, invalidCredentials, emailNotConfirmed, otpInvalid, otpExpired, rateLimited, signUpDisabled, cancelled, network, unknown }

class AuthFailure implements Exception {
  const AuthFailure(this.code, [this.message = '']);
  final AuthFailureCode code;
  final String message;

  @override
  String toString() => 'AuthFailure($code${message.isEmpty ? '' : ': $message'})';
}

/// Used when the build has no SUPABASE_URL / key: the app opens and every sign-in attempt says
/// "Sign-in is not set up in this build" instead of crashing.
class UnconfiguredAuthBackend implements AuthBackend {
  const UnconfiguredAuthBackend();
  static const _f = AuthFailure(AuthFailureCode.notConfigured, 'Supabase is not configured');

  @override
  bool get hasSession => false;
  @override
  String? get accessToken => null;
  @override
  AuthIdentity? get identity => null;
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<String?> refresh() async => null;
  @override
  Future<void> sendPhoneOtp(String e164Phone) => Future.error(_f);
  @override
  Future<void> verifyPhoneOtp(String e164Phone, String code) => Future.error(_f);
  @override
  Future<void> signInWithEmail(String email, String password) => Future.error(_f);
  @override
  Future<void> signInWithGoogle() => Future.error(_f);
  @override
  Future<void> sendPasswordReset(String email) => Future.error(_f);
  @override
  Future<void> resendEmailConfirmation(String email) => Future.error(_f);
  @override
  Future<void> signOut() async {}
}
