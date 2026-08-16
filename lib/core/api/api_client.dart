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
      // 🔴 ห้าม retry เส้นทางสมัคร/ล็อกอิน
      //
      // สมัครสมาชิกไม่ idempotent: ถ้าคำขอแรกถึงเซิร์ฟเวอร์และสร้างบัญชี
      // สำเร็จแต่คำตอบหายกลางทาง การ retry จะได้ 422 'อีเมลนี้เคยสมัครไว้แล้ว'
      // ผู้ใช้เห็น error คิดว่าสมัครไม่ผ่าน ไปสมัครใหม่ด้วยอีเมลอื่น เกิดบัญชีค้าง
      // และ token ของรอบแรกไม่เคยถูกเก็บ (จึงเข้าใช้บัญชีนั้นไม่ได้อีกเลย)
      //
      // ล็อกอินก็ไม่ควร retry เงียบ ๆ เพราะแต่ละครั้งนับเป็นความพยายามที่
      // ชน rate limit ฝั่งเซิร์ฟเวอร์ (throttle:auth-login) โดยผู้ใช้ไม่รู้ตัว
      retryEvaluator: (error, attempt) {
        final path = error.requestOptions.path;
        if (path.startsWith('/v1/auth/')) return false;
        return DefaultRetryEvaluator(defaultRetryableStatuses).evaluate(error, attempt);
      },
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

  /// POST helper.
  ///
  /// [idempotencyKey] สำคัญมากกับ endpoint ที่ตัดเงิน: RetryInterceptor
  /// ด้านล่างจะ retry POST อัตโนมัติเมื่อ timeout/5xx ถ้าคำขอแรกถึงเซิร์ฟเวอร์
  /// และถูกประมวลผลไปแล้วแต่คำตอบหายกลางทาง การ retry จะกลายเป็นข้อความซ้ำ
  /// และถูกคิดเงินสองรอบ ส่ง header นี้ไปด้วยเพื่อให้ backend (guardCharge)
  /// กันซ้ำได้จริง — ค่าเดิมต้องถูกใช้ซ้ำเมื่อผู้ใช้กด "ลองใหม่" ข้อความเดิม
  Future<T> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? query,
    String? idempotencyKey,
  }) async {
    try {
      final res = await dio.post(
        path,
        data: data,
        queryParameters: query,
        options: idempotencyKey == null
            ? null
            : Options(headers: {'Idempotency-Key': idempotencyKey}),
      );
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
  ///
  /// [idempotencyKey] จำเป็นเท่ากับใน [post] — เส้นทางที่หักเงิน (ลายมือ
  /// อัปรูปฝ่ามือ) ก็วิ่งผ่านที่นี่ และ RetryInterceptor ก็ retry ให้เหมือนกัน
  /// ก่อนหน้านี้เมธอดนี้ไม่รับคีย์เลย เน็ตสะดุดครั้งเดียวจึงถูกคิดเงินซ้ำได้
  Future<T> postMultipart<T>(
    String path, {
    required dynamic formData,
    String? idempotencyKey,
  }) async {
    try {
      final res = await dio.post(
        path,
        data: formData,
        options: Options(
          headers: idempotencyKey == null
              ? null
              : {'Idempotency-Key': idempotencyKey},
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
      // 🔴 `validateStatus: s < 500` ทำให้ 4xx ไม่ถูกโยนเป็น DioException
      // เส้นทางนี้จึงเป็นตัวสร้าง ApiException เองสำหรับ 4xx **ทั้งหมด**
      // ของเดิมส่งแค่ statusCode + message ทิ้ง reason_code และ body ไป
      // ผลคือ `e.reasonCode` เป็น null เสมอสำหรับ 4xx และกิ่งที่แยกเคสด้วย
      // reasonCode ตายหมด (เช่น 429 daily_limit ถูกแสดงเป็น "พิมพ์เร็วเกินไป"
      // และ 409 สามความหมายขึ้นข้อความเดียวกัน)
      final body = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : null;

      throw ApiException(
        statusCode: res.statusCode ?? 0,
        message: _extractMessage(res.data),
        reasonCode: body?['reason_code'] is String
            ? body!['reason_code'] as String
            : null,
        body: body,
      );
    }
    return res.data as T;
  }

  String _extractMessage(dynamic body) {
    if (body is Map) {
      // ข้อความรายช่องจาก Laravel validator — เซิร์ฟเวอร์เขียนข้อความไทยดี ๆ
      // ไว้ครบ (เช่น 'อีเมลนี้เคยสมัครไว้แล้ว — ลองเข้าสู่ระบบนะคะ') แต่ของเดิม
      // อ่านแค่ `message` ผู้ใช้จึงเห็นแค่ 'ข้อมูลไม่ถูกต้อง' ลอย ๆ ตอนสมัคร
      final errors = body['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final lines = <String>[];
        for (final v in errors.values) {
          if (v is List && v.isNotEmpty) {
            lines.add(v.first.toString());
          } else if (v is String) {
            lines.add(v);
          }
        }
        if (lines.isNotEmpty) return lines.join('\n');
      }
      if (body['message'] is String) return body['message'] as String;
      if (body['error'] is String) return body['error'] as String;
    }
    return 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง';
  }
}

final apiClientProvider = FutureProvider<ApiClient>((ref) async {
  return ApiClient.create();
});
