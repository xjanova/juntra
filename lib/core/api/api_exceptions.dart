import 'package:dio/dio.dart';

class ApiException implements Exception {
  ApiException({
    required this.statusCode,
    required this.message,
    this.reasonCode,
    this.body,
  });

  final int statusCode;
  final String message;

  /// รหัสเหตุผลจาก backend เช่น `daily_limit`, `insufficient_funds`,
  /// `in_flight` — จำเป็นเพราะ HTTP code เดียวกันหมายถึงคนละเรื่องได้
  /// (429 = ครบโควตาคุยฟรีวันนี้ หรือ ส่งถี่เกินไป ซึ่งต้องบอกผู้ใช้คนละแบบ)
  final String? reasonCode;

  /// body ดิบ เผื่อหน้าจอต้องใช้ค่าอื่น เช่น daily_left / balance
  final Map<String, dynamic>? body;

  factory ApiException.fromDio(DioException e) {
    final code = e.response?.statusCode ?? 0;
    final raw = e.response?.data;
    final body = raw is Map ? Map<String, dynamic>.from(raw) : null;

    String msg;
    if (body != null && body['message'] is String) {
      msg = body['message'] as String;
    } else if (body != null && body['error'] is String) {
      msg = body['error'] as String;
    } else if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      msg = 'หมดเวลาเชื่อมต่อ ตรวจสอบสัญญาณและลองใหม่';
    } else if (e.type == DioExceptionType.connectionError) {
      msg = 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้';
    } else {
      // Generic — the raw DioException message can carry the request URL /
      // host and other internals we must not surface to the user.
      msg = 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง';
    }

    return ApiException(
      statusCode: code,
      message: msg,
      reasonCode: body != null && body['reason_code'] is String
          ? body['reason_code'] as String
          : null,
      body: body,
    );
  }

  @override
  String toString() => 'ApiException($statusCode): $message';
}
