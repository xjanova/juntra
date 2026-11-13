import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session.dart';
import 'api_client.dart';
import 'api_exceptions.dart';
import 'app_config_repository.dart';
import 'endpoints.dart';

/// ไพ่ฟรี 1 ใบ (เว็บ /tarot/free · docs/API_PARITY_2026-11.md §D)
///
/// เซิร์ฟเวอร์เป็นคนเปิดไพ่ (`FreeTarotController@cast`) — แอพไม่เลือกไพ่เอง
/// AI ล้ม = เซิร์ฟเวอร์คืนสิทธิ์ให้ (ลูกค้ามีโอกาสเดียว) แอพจึงให้กดลองใหม่ได้เสมอ
class FreeCardRepository {
  FreeCardRepository(this._api);
  final ApiClient _api;

  /// สิทธิ์ของผู้ใช้คนนี้ — 404 (เซิร์ฟเวอร์เก่า) คืน [FreeCardState.unsupported] ไม่โยน
  Future<FreeCardState> status() async {
    try {
      final res = await _api.get<Map<String, dynamic>>(Api.tarotFree);
      final data = res['data'];
      return FreeCardState.fromJson(data is Map ? Map<String, dynamic>.from(data) : res);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return FreeCardState.unsupported;
      rethrow;
    }
  }

  /// เปิดไพ่ฟรี → คำทำนาย + ห้องถามฟรี (`conversation_id`)
  ///
  /// [idempotencyKey] — กดรัว/เน็ตหลุดแล้วกดใหม่ต้องได้ไพ่ใบเดิม ไม่ใช่กินสิทธิ์รอบใหม่
  Future<FreeCardResult> claim({String? question, required String idempotencyKey}) async {
    final q = question?.trim() ?? '';
    final res = await _api.post<Map<String, dynamic>>(
      Api.tarotFree,
      idempotencyKey: idempotencyKey,
      data: {if (q.isNotEmpty) 'question': q},
    );
    final result = FreeCardResult.fromJson(res);
    if (result == null) {
      throw ApiException(statusCode: 500, message: 'ไม่ได้รับคำทำนายจากเซิร์ฟเวอร์ กรุณาลองใหม่อีกครั้ง');
    }
    return result;
  }
}

/// สิทธิ์ไพ่ฟรี — `{available, reason: claimed|disabled|daily_cap|null, max_chars}`
@immutable
class FreeCardState {
  const FreeCardState({
    required this.available,
    this.reason,
    this.maxChars,
    this.message,
    this.readingId,
    this.supported = true,
  });

  /// เซิร์ฟเวอร์ยังไม่มีเส้นนี้ (404) → หน้าจอบอก "ยังไม่เปิดให้บริการ"
  static const unsupported = FreeCardState(available: false, supported: false);

  final bool available;

  /// claimed (เว็บเรียก used) · disabled · daily_cap · in_flight · no_token · guest
  final String? reason;

  /// ความยาวคำตอบ AI สูงสุดจากเซิร์ฟเวอร์ (ไม่ใช่ความยาวคำถาม)
  final int? maxChars;

  /// ข้อความไทยของเซิร์ฟเวอร์ (ถ้ามี) — ใช้ก่อนข้อความในแอพเสมอ
  final String? message;

  /// คำทำนายฟรีที่เคยรับไปแล้ว (เปิดดูซ้ำได้)
  final int? readingId;
  final bool supported;

  bool get claimed => reason == 'claimed' || reason == 'used';
  bool get disabled => reason == 'disabled';
  bool get inFlight => reason == 'in_flight';
  bool get needsLogin => reason == 'guest' || reason == 'no_token';

  factory FreeCardState.fromJson(Map<String, dynamic> j) {
    final max = j['max_chars'];
    final rid = j['reading_id'];
    return FreeCardState(
      available: j['available'] == true,
      reason: (j['reason'] is String && (j['reason'] as String).isNotEmpty) ? j['reason'] as String : null,
      maxChars: max is num && max > 0 ? max.toInt() : null,
      message: (j['message'] is String && (j['message'] as String).trim().isNotEmpty) ? j['message'] as String : null,
      readingId: rid is num ? rid.toInt() : null,
    );
  }

  /// ข้อความบอกเหตุที่เปิดไม่ได้ — ข้อความของเซิร์ฟเวอร์มาก่อน · ไม่มีใช้ถ้อยคำเดียวกับเว็บ
  /// (FreeReadingPolicy::gate) · [reader] = ชื่อผู้อ่านไพ่ 1 ใบ ("น้องบุษบา" / "แม่หมอ")
  String reasonText({String reader = 'แม่หมอ'}) {
    final m = message;
    if (m != null) return m;
    return freeCardReasonText(reason, reader: reader);
  }
}

/// ถ้อยคำของเว็บต่อรหัสเหตุผล (ใช้ "คุณ" ตามกติกาเว็บ 2026-11-10)
String freeCardReasonText(String? reason, {String reader = 'แม่หมอ'}) => switch (reason) {
      'claimed' || 'used' => 'คุณรับคำทำนายฟรีของรอบนี้ไปแล้วค่ะ',
      'disabled' => 'ตอนนี้$readerปิดรอบดูดวงฟรีชั่วคราวค่ะ',
      'daily_cap' => 'วันนี้$readerเปิดไพ่ฟรีครบจำนวนแล้วค่ะ พรุ่งนี้มาใหม่นะคะ',
      'in_flight' => '$readerกำลังเปิดไพ่ให้อยู่ค่ะ รอสักครู่นะคะ',
      'no_token' => 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่อีกครั้งค่ะ',
      'guest' => 'กรุณาเข้าสู่ระบบเพื่อรับคำทำนายฟรีค่ะ',
      _ => 'ตอนนี้ยังเปิดไพ่ฟรีให้ไม่ได้ค่ะ',
    };

/// ผลการเปิดไพ่ฟรี — `{data: {reading, conversation_id}}`
@immutable
class FreeCardResult {
  const FreeCardResult({required this.readingId, this.conversationId, this.reading = const {}});
  final int readingId;

  /// ห้องถามฟรีของไพ่ใบนี้ (เว็บ chat.from-free) — null = เซิร์ฟเวอร์ไม่ได้เปิดห้องให้
  final int? conversationId;
  final Map<String, dynamic> reading;

  static FreeCardResult? fromJson(Map<String, dynamic> res) {
    final data = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : res;
    final reading = data['reading'] is Map ? Map<String, dynamic>.from(data['reading'] as Map) : const <String, dynamic>{};
    final id = reading['id'] ?? data['reading_id'];
    if (id is! num) return null;
    final cid = data['conversation_id'];
    return FreeCardResult(
      readingId: id.toInt(),
      conversationId: cid is num ? cid.toInt() : null,
      reading: reading,
    );
  }
}

final freeCardRepositoryProvider = FutureProvider<FreeCardRepository>((ref) async {
  final api = await ref.watch(apiClientProvider.future);
  return FreeCardRepository(api);
});

/// สิทธิ์ไพ่ฟรีของผู้ใช้ที่ล็อกอินอยู่ — ออกจากระบบ/สลับบัญชีแล้วโหลดใหม่ (null = ยังไม่ล็อกอิน)
final freeCardStatusProvider = FutureProvider.autoDispose<FreeCardState?>((ref) async {
  if (ref.watch(sessionUserIdProvider) == null) return null;
  final config = ref.watch(appConfigValueProvider);
  if (!config.has('free_reading') || !config.freeReading) return FreeCardState.unsupported;
  final repo = await ref.watch(freeCardRepositoryProvider.future);
  return repo.status();
});

/// ห้องถามฟรีของไพ่ฟรีที่เพิ่งเปิดในรอบนี้ (reading id → conversation id)
///
/// หน้าผลรู้แค่ id ของคำทำนาย — ใช้ค่านี้พาไปห้องที่เซิร์ฟเวอร์เปิดไว้ให้ (มีนาฬิกาถามฟรี)
/// ล้างทิ้งเมื่อสลับผู้ใช้ ไม่ให้คนถัดไปกดเข้าห้องของคนก่อน
final freeCardConversationsProvider = StateProvider<Map<int, int>>((ref) {
  ref.watch(sessionUserIdProvider);
  return const {};
});
