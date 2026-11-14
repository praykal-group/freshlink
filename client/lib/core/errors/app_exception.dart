/// Every failure the UI sees: the server's error envelope `{error:{code,message,details}}` mapped
/// to one type (Section 10.2), plus client-side codes (NETWORK, TIMEOUT, ...).
class AppException implements Exception {
  const AppException(this.code, this.message, {this.status, this.details = const {}});

  final String code;
  final String message;

  /// HTTP status, or null when no response arrived.
  final int? status;
  final Map<String, dynamic> details;

  static const network = 'NETWORK';
  static const timeout = 'TIMEOUT';
  static const unknown = 'UNKNOWN';
  static const upgradeRequired = 'UPGRADE_REQUIRED';
  static const wrongAppForRole = 'WRONG_APP_FOR_ROLE';
  static const notRegistered = 'NOT_REGISTERED';
  static const sessionOnOtherDevice = 'SESSION_ON_OTHER_DEVICE';
  static const unauthorized = 'UNAUTHORIZED';

  /// No response or a server/throttling error: try again later.
  bool get isTransient => status == null || status! >= 500 || status == 408 || status == 429;

  /// 4xx except 408/429: retrying the same request will not help (Section 10.2 sync rules).
  bool get isPermanent => !isTransient;

  @override
  String toString() => 'AppException($code${status == null ? '' : ', $status'}): $message';
}
