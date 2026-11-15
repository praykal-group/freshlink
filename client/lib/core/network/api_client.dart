import 'dart:async';

import 'package:dio/dio.dart';

import '../errors/app_exception.dart';
import '../utils/backoff.dart';
import '../utils/single_flight.dart';

/// Where the bearer token comes from (Supabase session). `refresh` returns the new access token,
/// or null when the session cannot be refreshed (signed out).
abstract class TokenSource {
  String? get accessToken;
  Future<String?> refresh();
}

/// Section 6.1 headers sent on every call.
class ClientInfo {
  const ClientInfo({required this.flavor, required this.versionCode, required this.deviceId, required this.language});
  final String flavor;
  final int versionCode;
  final String deviceId;
  final String Function() language;
}

/// Events the whole app reacts to, whichever request triggered them.
sealed class ApiEvent {
  const ApiEvent();
}

/// 426: this version is below minSupportedVersionCode → mandatory update screen (Section 12.4).
class UpgradeRequiredEvent extends ApiEvent {
  const UpgradeRequiredEvent();
}

/// 409 SESSION_ON_OTHER_DEVICE (driver single-device rule) or 403 WRONG_APP_FOR_ROLE / NOT_REGISTERED.
class SessionRevokedEvent extends ApiEvent {
  const SessionRevokedEvent(this.error);
  final AppException error;
}

const _kAuthRetried = 'iccms.authRetried';
const _kGetAttempt = 'iccms.getAttempt';

/// The one HTTP client of the app (Section 10.2 core/network):
/// - bearer token; on 401 one single-flight refresh, then the request is retried once
/// - GET retried with backoff on network/5xx/408/429 (3 tries); other methods never retried here
///   (writes go through the outbox, which is idempotent on clientOpId)
/// - 426 → [UpgradeRequiredEvent]; error envelope → [AppException]
class ApiClient {
  ApiClient({
    required String baseUrl,
    required this.info,
    required this.tokens,
    HttpClientAdapter? adapter,
    Future<void> Function(Duration)? sleep,
    double Function()? random,
  })  : _sleep = sleep ?? Future<void>.delayed,
        _random = random, // ignore: prefer_initializing_formals
        dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 20),
          contentType: Headers.jsonContentType,
          responseType: ResponseType.json,
        )) {
    if (adapter != null) dio.httpClientAdapter = adapter;
    dio.interceptors.add(InterceptorsWrapper(onRequest: _onRequest, onError: _onError));
  }

  final Dio dio;
  final ClientInfo info;
  final TokenSource tokens;
  final Future<void> Function(Duration) _sleep;
  final double Function()? _random;
  final _refresh = SingleFlight<String?>();
  final _events = StreamController<ApiEvent>.broadcast();

  Stream<ApiEvent> get events => _events.stream;

  /// For tests: how many refreshes actually ran.
  int refreshCount = 0;

  void _onRequest(RequestOptions o, RequestInterceptorHandler h) {
    o.headers['X-App-Flavor'] = info.flavor;
    o.headers['X-App-Version-Code'] = '${info.versionCode}';
    o.headers['X-Device-Id'] = info.deviceId;
    o.headers['Accept-Language'] = info.language();
    final token = tokens.accessToken;
    if (token != null && !o.headers.containsKey('Authorization')) o.headers['Authorization'] = 'Bearer $token';
    h.next(o);
  }

  Future<void> _onError(DioException e, ErrorInterceptorHandler h) async {
    final o = e.requestOptions;
    final status = e.response?.statusCode;

    if (status == 401 && o.extra[_kAuthRetried] != true) {
      final token = await _refresh.run(() async {
        refreshCount++;
        try {
          return await tokens.refresh();
        } catch (_) {
          return null;
        }
      });
      if (token != null) {
        o.extra[_kAuthRetried] = true;
        o.headers['Authorization'] = 'Bearer $token';
        try {
          return h.resolve(await dio.fetch(o));
        } on DioException catch (retryError) {
          return h.next(retryError);
        }
      }
      return h.next(e);
    }

    if (status == 426) _events.add(const UpgradeRequiredEvent());
    final code = _envelope(e.response?.data)?['code'];
    if ((status == 409 && code == AppException.sessionOnOtherDevice) || (status == 403 && (code == AppException.wrongAppForRole || code == AppException.notRegistered))) {
      _events.add(SessionRevokedEvent(toAppException(e)));
    }

    final transient = status == null ? _isNetwork(e) : (status >= 500 || status == 408 || status == 429);
    final attempt = (o.extra[_kGetAttempt] as int?) ?? 1;
    if (o.method == 'GET' && transient && attempt < apiGetMaxTries) {
      await _sleep(apiGetBackoff.delay(attempt, random: _random?.call()));
      o.extra[_kGetAttempt] = attempt + 1;
      try {
        return h.resolve(await dio.fetch(o));
      } on DioException catch (retryError) {
        return h.next(retryError);
      }
    }
    h.next(e);
  }

  static bool _isNetwork(DioException e) =>
      e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      e.type == DioExceptionType.unknown;

  static Map<String, dynamic>? _envelope(Object? data) {
    if (data is Map && data['error'] is Map) return Map<String, dynamic>.from(data['error'] as Map);
    return null;
  }

  /// Error envelope `{error:{code,message,details}}` → AppException (Section 6.1).
  static AppException toAppException(DioException e) {
    final status = e.response?.statusCode;
    final env = _envelope(e.response?.data);
    if (env != null) {
      return AppException(
        '${env['code'] ?? AppException.unknown}',
        '${env['message'] ?? 'Request failed'}',
        status: status,
        details: env['details'] is Map ? Map<String, dynamic>.from(env['details'] as Map) : const {},
      );
    }
    if (status == null) {
      final timeout = e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout || e.type == DioExceptionType.sendTimeout;
      return AppException(timeout ? AppException.timeout : AppException.network, e.message ?? 'No connection', status: null);
    }
    return AppException(status == 426 ? AppException.upgradeRequired : 'HTTP_$status', e.message ?? 'Request failed', status: status);
  }

  Future<dynamic> _call(Future<Response<dynamic>> Function() send) async {
    try {
      return (await send()).data;
    } on DioException catch (e) {
      throw toAppException(e);
    }
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) => _call(() => dio.get(path, queryParameters: query));
  Future<dynamic> post(String path, {Object? body}) => _call(() => dio.post(path, data: body));
  Future<dynamic> patch(String path, {Object? body}) => _call(() => dio.patch(path, data: body));
  Future<dynamic> put(String path, {Object? body}) => _call(() => dio.put(path, data: body));
  Future<dynamic> delete(String path) => _call(() => dio.delete(path));

  /// Presigned S3 PUT: absolute URL, exactly the signed headers, no bearer token (Section 6.4 Files).
  Future<void> putToPresignedUrl(String url, Stream<List<int>> body, Map<String, String> headers) async {
    final plain = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), sendTimeout: const Duration(minutes: 2)));
    plain.httpClientAdapter = dio.httpClientAdapter;
    try {
      await plain.put<void>(url, data: body, options: Options(headers: headers, contentType: headers['Content-Type']));
    } on DioException catch (e) {
      throw toAppException(e);
    }
  }

  void dispose() {
    _events.close();
    dio.close(force: true);
  }
}
