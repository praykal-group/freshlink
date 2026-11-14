/// Shared form validators (Section 10.2, FO-NFR-07). Each returns an error key (looked up in
/// AppLocalizations by the field widget) or null when valid. Keys, not text, so validation stays
/// testable without a BuildContext and every message is translated.
enum ValidationError {
  required,
  phoneInvalid,
  otpInvalid,
  emailInvalid,
  passwordTooShort,
  notANumber,
  belowMin,
  aboveMax,
}

class ValidationResult {
  const ValidationResult(this.error, {this.limit});
  final ValidationError error;

  /// The bound that was crossed (for belowMin / aboveMax messages).
  final num? limit;

  @override
  bool operator ==(Object other) => other is ValidationResult && other.error == error && other.limit == limit;

  @override
  int get hashCode => Object.hash(error, limit);

  @override
  String toString() => 'ValidationResult($error${limit == null ? '' : ', $limit'})';
}

class Validators {
  const Validators._();

  static final _digits = RegExp(r'^\d+$');
  static final _email = RegExp(r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$");

  /// Indian mobile number typed after the fixed +91 prefix: 10 digits starting with 6–9.
  static ValidationResult? indianMobile(String? v) {
    final s = (v ?? '').replaceAll(RegExp(r'[\s-]'), '');
    if (s.isEmpty) return const ValidationResult(ValidationError.required);
    if (s.length != 10 || !_digits.hasMatch(s) || !'6789'.contains(s[0])) return const ValidationResult(ValidationError.phoneInvalid);
    return null;
  }

  /// E.164 for the API: "+91" + the 10 digits.
  static String toE164India(String v) => '+91${v.replaceAll(RegExp(r'[\s-]'), '')}';

  /// Supabase OTP: 6 digits (AUTH-02).
  static ValidationResult? otp(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return const ValidationResult(ValidationError.required);
    return s.length == 6 && _digits.hasMatch(s) ? null : const ValidationResult(ValidationError.otpInvalid);
  }

  static ValidationResult? email(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return const ValidationResult(ValidationError.required);
    return _email.hasMatch(s) && s.length <= 254 ? null : const ValidationResult(ValidationError.emailInvalid);
  }

  static ValidationResult? password(String? v, {int min = 8}) {
    if ((v ?? '').isEmpty) return const ValidationResult(ValidationError.required);
    return v!.length >= min ? null : ValidationResult(ValidationError.passwordTooShort, limit: min);
  }

  /// Numeric field with ranges from the products master (e.g. core temperature, weight).
  /// Accepts "," as decimal separator (Indian keyboards in some languages).
  static ValidationResult? numberInRange(String? v, {num? min, num? max, bool required = true}) {
    final s = (v ?? '').trim().replaceAll(',', '.');
    if (s.isEmpty) return required ? const ValidationResult(ValidationError.required) : null;
    final n = num.tryParse(s);
    if (n == null || n.isNaN || n.isInfinite) return const ValidationResult(ValidationError.notANumber);
    if (min != null && n < min) return ValidationResult(ValidationError.belowMin, limit: min);
    if (max != null && n > max) return ValidationResult(ValidationError.aboveMax, limit: max);
    return null;
  }
}
