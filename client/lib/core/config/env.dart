import 'app_flavor.dart';

/// Build-time configuration from `--dart-define-from-file=env/<env>.json` (Section 11). Only
/// non-secret values: the Supabase publishable key is safe in clients; the service role key never is.
class Env {
  const Env._();

  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:3000/api/v1');
  static const wsUrl = String.fromEnvironment('WS_URL', defaultValue: 'ws://10.0.2.2:3000/rt');
  static const updateChannel = String.fromEnvironment('UPDATE_CHANNEL', defaultValue: 'stable');
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  /// OAuth redirect for the manager APK (Supabase redirect URL list, Section 6.2).
  static const managerAuthCallback = 'in.iccms.manager://login-callback';

  // Firebase without google-services.json (D-120): the options come from the env file. Each flavor
  // is its own Firebase Android app, so the app id is per flavor.
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const firebaseSenderId = String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const _firebaseAppIdDriver = String.fromEnvironment('FIREBASE_APP_ID_DRIVER');
  static const _firebaseAppIdOperator = String.fromEnvironment('FIREBASE_APP_ID_OPERATOR');
  static const _firebaseAppIdManager = String.fromEnvironment('FIREBASE_APP_ID_MANAGER');

  static bool get supabaseConfigured => supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  static String firebaseAppId(AppFlavor f) => switch (f) {
        AppFlavor.driver => _firebaseAppIdDriver,
        AppFlavor.operator => _firebaseAppIdOperator,
        AppFlavor.manager => _firebaseAppIdManager,
      };

  static bool firebaseConfigured(AppFlavor f) => firebaseApiKey.isNotEmpty && firebaseProjectId.isNotEmpty && firebaseSenderId.isNotEmpty && firebaseAppId(f).isNotEmpty;
}
