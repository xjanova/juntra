import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import 'api_exceptions.dart';

/// Base URL for the juntraweb (จันทรา.online) Laravel backend.
///
/// All chat / wallet / membership / history flows go through juntraweb,
/// which in turn proxies AI calls to the Thaiprompt-Affiliate API pool
/// (juntra app holds NO upstream AI keys — see CLAUDE.md hard rule #2).
///
/// Override at build time, e.g. for staging or a local Laragon dev:
///   flutter build apk --dart-define=JUNTRA_API_BASE=https://จันทรา.online/api
///   flutter run --dart-define=JUNTRA_API_BASE=http://10.0.2.2:8000/api
///
/// The default host is the PUNYCODE form of จันทรา.online
/// (`xn--82c4af5bzdj.online`) — the exact same domain, Cloudflare origin and
/// TLS certificate, only ASCII. Dart's `HttpClient` on Android does NOT
/// ToASCII-encode a Thai IDN host, so `https://จันทรา.online/...` fails DNS
/// resolution on real devices → every API call silently fails (the app falls
/// back to offline behaviour and looks "stuck"). Punycode resolves on every
/// network. The user never sees this host — no UI renders it.
const String _kApiBase = String.fromEnvironment(
  'JUNTRA_API_BASE',
  defaultValue: 'https://xn--82c4af5bzdj.online/api',
);

/// Token storage key — same scheme as thaipromptapp so we could share
/// a session if both apps were installed by the same user (future-proof).
const String _kTokenKey = 'juntra_auth_token';

class ApiClient {
  ApiClient._(this.dio, this._storage);
  final Dio dio;
  final FlutterSecureStorage _storage;

  static Future<ApiClient> create() async {
    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );

    final dio = Dio(BaseOptions(
      baseUrl: _kApiBase,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
      headers: const {
        'Accept': 'application/json',
        'X-Client': 'juntra-android',
      },
      // Don't throw on 4xx — let callers inspect status + body.
      validateStatus: (s) => s != null && s < 500,
    ));

    // Attach Bearer token (Sanctum) when present + clear on 401 so a
    // server-side token revocation doesn't leave the client wedged with
    // a stale credential forever.
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await storage.read(key: _kTokenKey);
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onResponse: (response, handler) async {
        if (response.statusCode == 401) {
          await storage.delete(key: _kTokenKey);
        }
        handler.next(response);
      },
    ));

    // Retry transient failures (timeouts, 5xx) — cheap insurance for
    // Thai mobile networks where signal flickers.
    dio.interceptors.add(RetryInterceptor(
      dio: dio,
      retries: 2,
      retryDelays: const [
        Duration(milliseconds: 600),
        Duration(milliseconds: 1500),
      ],
    ));

    if (kDebugMode) {
      dio.interceptors.add(PrettyDioLogger(
        requestHeader: false,
        requestBody: true,
        responseHeader: false,
        responseBody: false,
        compact: true,
        maxWidth: 100,
      ));
    }

    return ApiClient._(dio, storage);
  }

  Future<void> setToken(String token) =>
      _storage.write(key: _kTokenKey, value: token);

  Future<String?> getToken() => _storage.read(key: _kTokenKey);

  Future<void> clearToken() => _storage.delete(key: _kTokenKey);

  /// GET helper with automatic JSON decoding + error mapping.
  Future<T> get<T>(String path, {Map<String, dynamic>? query}) async {
    try {
      final res = await dio.get(path, queryParameters: query);
      return _decode<T>(res);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<T> post<T>(String path, {dynamic data, Map<String, dynamic>? query}) async {
    try {
      final res = await dio.post(path, data: data, queryParameters: query);
      return _decode<T>(res);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<T> delete<T>(String path, {dynamic data, Map<String, dynamic>? query}) async {
    try {
      final res = await dio.delete(path, data: data, queryParameters: query);
      return _decode<T>(res);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// Multipart POST. Used by the native slip upload — `formData` is a
  /// Dio [FormData] including a [MultipartFile] under the field name
  /// the backend expects. Returns the decoded JSON body, same as [post].
  Future<T> postMultipart<T>(String path, {required dynamic formData}) async {
    try {
      final res = await dio.post(
        path,
        data: formData,
        options: Options(
          // Let Dio set Content-Type with the multipart boundary —
          // overriding it strips the boundary parameter and the server
          // can't parse the form.
          contentType: 'multipart/form-data',
          // Higher receive timeout because slip uploads from flaky
          // mobile networks can take longer than a typical JSON POST.
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 60),
        ),
      );
      return _decode<T>(res);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  T _decode<T>(Response res) {
    if (res.statusCode != null && res.statusCode! >= 400) {
      throw ApiException(
        statusCode: res.statusCode ?? 0,
        message: _extractMessage(res.data),
      );
    }
    return res.data as T;
  }

  String _extractMessage(dynamic body) {
    if (body is Map && body['message'] is String) return body['message'] as String;
    if (body is Map && body['error'] is String) return body['error'] as String;
    return 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง';
  }
}

final apiClientProvider = FutureProvider<ApiClient>((ref) async {
  return ApiClient.create();
});
