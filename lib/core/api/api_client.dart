import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import 'api_exceptions.dart';

/// Base URL for the Thaiprompt-Affiliate Laravel backend.
///
/// Override at build time:
///   flutter build apk --dart-define=JUNTRA_API_BASE=https://main.thaiprompt.online/api
const String _kApiBase = String.fromEnvironment(
  'JUNTRA_API_BASE',
  defaultValue: 'https://main.thaiprompt.online/api',
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

    // Attach Bearer token (Sanctum) when present.
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await storage.read(key: _kTokenKey);
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
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
