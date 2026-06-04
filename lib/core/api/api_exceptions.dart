import 'package:dio/dio.dart';

class ApiException implements Exception {
  ApiException({required this.statusCode, required this.message});
  final int statusCode;
  final String message;

  factory ApiException.fromDio(DioException e) {
    final code = e.response?.statusCode ?? 0;
    final body = e.response?.data;
    String msg;
    if (body is Map && body['message'] is String) {
      msg = body['message'] as String;
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
    return ApiException(statusCode: code, message: msg);
  }

  @override
  String toString() => 'ApiException($statusCode): $message';
}
