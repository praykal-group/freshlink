// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get languageName => 'English';

  @override
  String get loading => 'Loading…';

  @override
  String get loginTitle => 'Sign in';

  @override
  String get loginSubtitlePhone =>
      'Use the mobile number your manager registered.';

  @override
  String get phoneLabel => 'Mobile number';

  @override
  String get phoneHelper => 'We will send a 6-digit code by SMS';

  @override
  String get sendCode => 'Send code';

  @override
  String get language => 'Language';

  @override
  String get otpTitle => 'Enter the code';

  @override
  String otpSentTo(String phone) {
    return 'Code sent to $phone';
  }

  @override
  String get otpLabel => '6-digit code';

  @override
  String get verify => 'Verify';

  @override
  String resendIn(int seconds) {
    return 'Resend in $seconds s';
  }

  @override
  String get resendCode => 'Resend code';

  @override
  String get codeResent => 'A new code is on its way';

  @override
  String get changeNumber => 'Change number';

  @override
  String get continueWithGoogle => 'Continue with Google';

  @override
  String get orDivider => 'or';

  @override
  String get emailLabel => 'Email';

  @override
  String get passwordLabel => 'Password';

  @override
  String get signIn => 'Sign in';

  @override
  String get forgotPassword => 'Forgot password?';

  @override
  String get usePhoneInstead => 'Use phone OTP instead';

  @override
  String get useEmailInstead => 'Use email instead';

  @override
  String get resetSent =>
      'If this email has an account, a reset link is on its way.';

  @override
  String get verifyEmailTitle => 'Check your inbox';

  @override
  String verifyEmailBody(String email) {
    return 'We sent a confirmation link to $email. Open it, then sign in again.';
  }

  @override
  String get resendEmail => 'Resend email';

  @override
  String get emailResent => 'Email sent again';

  @override
  String get backToLogin => 'Back to sign in';

  @override
  String get errorRequired => 'Required';

  @override
  String get errorPhone => 'Enter a 10-digit mobile number';

  @override
  String get errorOtp => 'Enter the 6-digit code';

  @override
  String get errorEmail => 'Enter a valid email address';

  @override
  String errorPasswordShort(int min) {
    return 'At least $min characters';
  }

  @override
  String get errorNotANumber => 'Enter a number';

  @override
  String errorBelowMin(String min) {
    return 'Must be at least $min';
  }

  @override
  String errorAboveMax(String max) {
    return 'Must be at most $max';
  }

  @override
  String get authInvalidCredentials => 'Wrong email or password.';

  @override
  String get authEmailNotConfirmed =>
      'Confirm your email first. Check your inbox.';

  @override
  String get authOtpInvalid =>
      'That code is not right. Check the SMS and try again.';

  @override
  String get authOtpExpired => 'The code has expired. Ask for a new one.';

  @override
  String get authRateLimited =>
      'Too many attempts. Wait a few minutes and try again.';

  @override
  String get authNotRegistered =>
      'This number or email is not registered. Ask your manager.';

  @override
  String get authNetwork => 'No connection. Check the internet and try again.';

  @override
  String get authNotConfigured => 'Sign-in is not set up in this build.';

  @override
  String get authCancelled => 'Sign-in was cancelled.';

  @override
  String get authUnknown => 'Sign-in failed. Try again.';

  @override
  String get reasonWrongApp =>
      'Your account cannot use this app. Please use the app for your role.';

  @override
  String get reasonNotRegistered =>
      'Your account is not active. Contact your manager.';

  @override
  String get reasonOtherDevice =>
      'You logged in on another phone, so this phone was signed out.';

  @override
  String get reasonUnauthorized =>
      'Your session has ended. Please sign in again.';

  @override
  String reasonGeneric(String code) {
    return 'Could not sign in ($code). Try again.';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get themeSystem => 'Same as phone';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get settingsSync => 'Sync';

  @override
  String syncPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count changes waiting to sync',
      one: '1 change waiting to sync',
      zero: 'Everything is synced',
    );
    return '$_temp0';
  }

  @override
  String get openSyncQueue => 'Open sync queue';

  @override
  String get settingsAbout => 'About';

  @override
  String aboutVersion(String version, String code) {
    return 'Version $version (build $code)';
  }

  @override
  String get signOut => 'Sign out';

  @override
  String get signOutConfirm => 'Sign out of this phone?';

  @override
  String signOutPendingWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count changes have not synced yet. They stay on this phone and sync after you sign in again.',
      one:
          '1 change has not synced yet. It stays on this phone and syncs after you sign in again.',
    );
    return '$_temp0';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get syncQueueTitle => 'Sync queue';

  @override
  String get syncNow => 'Sync now';

  @override
  String get syncNeedsAttention => 'Needs attention';

  @override
  String get syncWaiting => 'Waiting to sync';

  @override
  String syncNextTry(String time) {
    return 'Next try at $time';
  }

  @override
  String get syncFiles => 'Files to upload';

  @override
  String get syncEmpty =>
      'Nothing is waiting. All your changes are on the server.';

  @override
  String get retry => 'Retry';

  @override
  String get discard => 'Discard';

  @override
  String get discardConfirm =>
      'Discard this change? The server refused it and it will be lost.';

  @override
  String get offlineBanner => 'Offline. Your changes are saved and will sync.';

  @override
  String get updatedJustNow => 'Updated just now';

  @override
  String updatedAgo(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'Updated $minutes min ago',
      one: 'Updated 1 min ago',
    );
    return '$_temp0';
  }

  @override
  String get errorTitle => 'Something went wrong';

  @override
  String get emptyTitle => 'Nothing here yet';

  @override
  String homeWelcome(String name) {
    return 'Hello, $name';
  }

  @override
  String get homeComingSoon =>
      'The screens of this app arrive in the next release.';

  @override
  String get updateRequiredTitle => 'Update required';

  @override
  String get updateRequiredBody =>
      'This version is no longer supported. Install the latest version to continue.';

  @override
  String get statusSafe => 'Safe';

  @override
  String get statusWatch => 'Watch';

  @override
  String get statusCritical => 'Critical';

  @override
  String get statusInfo => 'Info';

  @override
  String get voiceInput => 'Speak the value';
}
