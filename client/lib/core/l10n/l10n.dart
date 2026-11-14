import 'package:flutter/widgets.dart';

import '../../l10n/generated/app_localizations.dart';
import '../auth/auth_backend.dart';
import '../errors/app_exception.dart';
import '../utils/validators.dart';

export '../../l10n/generated/app_localizations.dart';

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

String _num(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// Validator results are codes; the text is chosen here, in the user's language.
String? validationText(AppLocalizations l, ValidationResult? r) {
  if (r == null) return null;
  return switch (r.error) {
    ValidationError.required => l.errorRequired,
    ValidationError.phoneInvalid => l.errorPhone,
    ValidationError.otpInvalid => l.errorOtp,
    ValidationError.emailInvalid => l.errorEmail,
    ValidationError.passwordTooShort => l.errorPasswordShort((r.limit ?? 8).toInt()),
    ValidationError.notANumber => l.errorNotANumber,
    ValidationError.belowMin => l.errorBelowMin(_num(r.limit ?? 0)),
    ValidationError.aboveMax => l.errorAboveMax(_num(r.limit ?? 0)),
  };
}

String authFailureText(AppLocalizations l, AuthFailureCode c) => switch (c) {
      AuthFailureCode.invalidCredentials => l.authInvalidCredentials,
      AuthFailureCode.emailNotConfirmed => l.authEmailNotConfirmed,
      AuthFailureCode.otpInvalid => l.authOtpInvalid,
      AuthFailureCode.otpExpired => l.authOtpExpired,
      AuthFailureCode.rateLimited => l.authRateLimited,
      AuthFailureCode.signUpDisabled => l.authNotRegistered,
      AuthFailureCode.network => l.authNetwork,
      AuthFailureCode.notConfigured => l.authNotConfigured,
      AuthFailureCode.cancelled => l.authCancelled,
      AuthFailureCode.unknown => l.authUnknown,
    };

/// Why the session ended (SignedOut.reason), shown once on the login screen.
String? signOutReasonText(AppLocalizations l, String? code) => switch (code) {
      null => null,
      AppException.wrongAppForRole => l.reasonWrongApp,
      AppException.notRegistered => l.reasonNotRegistered,
      AppException.sessionOnOtherDevice => l.reasonOtherDevice,
      AppException.unauthorized => l.reasonUnauthorized,
      AppException.network || AppException.timeout => l.authNetwork,
      _ => l.reasonGeneric(code),
    };
