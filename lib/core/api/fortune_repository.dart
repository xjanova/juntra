import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/data/tarot_deck.dart';
import 'api_client.dart';
import 'api_exceptions.dart';
import 'endpoints.dart';

/// Reading history — wraps `/v1/history/readings*`.
///
/// The shuffle-and-reveal cinematic happens client-side (it's the brand's
/// signature interaction), then [createTarotReading] hands the picked
/// cards to the backend which:
///   1. Debits the user's wallet (412 / 402 on insufficient balance)
///   2. Persists a Reading row + tarot_reading_cards
///   3. Calls FortuneAiService to generate the AI interpretation
///   4. Returns the full reading payload — same shape as [reading]
///
/// Credits / wallet balance live in [WalletRepository] now — the legacy
/// `/v1/fortune/credits` shape was retired when juntraweb consolidated
/// pricing under the wallet API.
class FortuneRepository {
  FortuneRepository(this._api);
  final ApiClient _api;

  /// List the user's recent readings.
  /// Returns `{data: List, meta: {next_cursor}}`.
  Future<Map<String, dynamic>> history({int limit = 20, String? cursor, String? type}) async {
    return _api.get<Map<String, dynamic>>(
      Api.historyReadings,
      query: {
        'limit': limit,
        'cursor': ?cursor,
        'type': ?type,
      },
    );
  }

  /// Get a single reading with cards (for tarot) and full AI interpretation.
  Future<Map<String, dynamic>> reading(int id) async {
    final res = await _api.get<Map<String, dynamic>>(Api.historyReading(id));
    final inner = res['data'];
    return inner is Map<String, dynamic> ? inner : res;
  }

  /// Persist a freshly-completed mobile tarot reading. The Flutter
  /// shuffle screen calls this once the user has revealed all picked
  /// cards; on success it routes to `/reading?id=<returned id>`.
  ///
  /// [type] — 'tarot_three' (3 cards) or 'tarot_celtic' (10 cards).
  /// [question] — optional intention text from Phase 1 of shuffle.
  /// [picks] — the picked TarotCards in pick order. Each card maps to
  /// its server-side slug via [TarotCard.slug]; reversed flag is chosen
  /// client-side at reveal time and passed through.
  ///
  /// Returns the same shape as [reading], merged with `balance` + `cost`
  /// so the caller can update the home greeting / wallet pill without
  /// a second /auth/me round-trip.
  ///
  /// Throws [ApiException] with statusCode:
  ///   - 402 → insufficient_funds (caller should route to /wallet)
  ///   - 422 → validation (bad slug, wrong pick count)
  ///   - 503 → reading_failed; wallet was refunded automatically
  /// [idempotencyKey] — **บังคับ** เพราะเส้นนี้ตัดเงิน RetryInterceptor
  /// ใน [ApiClient] retry POST เองเมื่อ timeout/5xx ถ้าคำขอแรกถึงเซิร์ฟเวอร์
  /// แล้วแต่คำตอบหายกลางทาง การ retry จะกลายเป็นการทำนายรอบใหม่และถูกคิดเงิน
  /// ซ้ำ ผู้เรียกต้องสร้างคีย์ครั้งเดียวต่อการเปิดไพ่หนึ่งครั้ง แล้วใช้ค่าเดิม
  /// ทุกครั้งที่กด "ลองใหม่"
  Future<Map<String, dynamic>> createTarotReading({
    required String type,
    String? question,
    required List<TarotPick> picks,
    required String idempotencyKey,
    String? dealToken,
    List<int>? slots,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      Api.historyReadings,
      idempotencyKey: idempotencyKey,
      data: {
        'type': type,
        if (question != null && question.trim().isNotEmpty) 'question': question.trim(),
        // เส้นทางหลัก: กองที่เซิร์ฟเวอร์สับ + ตำแหน่งที่แตะ — เซิร์ฟเวอร์แปลง
        // เป็นไพ่และทิศเอง ไคลเอนต์จึงบังคับผลไม่ได้
        if (dealToken != null && slots != null) ...{
          'deal_token': dealToken,
          'slots': slots,
        },
        // ส่ง picks ไปด้วยเสมอเพื่อรองรับกรณีที่กองหมดอายุ/ขอกองไม่ได้
        'picks': picks.map((p) => {
          'slug': p.card.slug,
          'reversed': p.reversed,
        }).toList(),
      },
    );
    final inner = res['data'];
    final reading = inner is Map<String, dynamic> ? inner : res;
    return {
      ...reading,
      if (res['balance'] != null) 'balance': res['balance'],
      if (res['cost'] != null) 'cost': res['cost'],
    };
  }

  /// Create a numerology reading → returns the new reading id (route to
  /// `/reading?id=`). Throws [ApiException] on 402/422/503 etc.
  Future<int> createNumerology({
    required String name,
    required String birthDate,
    required String idempotencyKey,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      Api.fortuneNumerology,
      idempotencyKey: idempotencyKey,
      data: {'name': name, 'birth_date': birthDate},
    );
    return _readingId(res);
  }

  /// หมวดงานมงคลทั้งหมด — `[{key, label}]`
  Future<List<Map<String, dynamic>>> occasions() async {
    final res = await _api.get<Map<String, dynamic>>(Api.fortuneOccasions);
    final data = res['data'];
    if (data is List) {
      return data.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    }
    // เซิร์ฟเวอร์อาจคืนเป็น map {key: label} — รองรับทั้งสองรูป
    if (data is Map) {
      return data.entries
          .map((e) => {'key': e.key.toString(), 'label': e.value.toString()})
          .toList();
    }
    return const [];
  }

  /// Create an auspicious-dates reading. The backend returns 422
  /// (`no_auspicious_day`) when the window has no good day → [ApiException].
  Future<int> createAuspicious({
    required String occasion,
    String? occasionType,
    String? fromDate,
    String? toDate,
    required String idempotencyKey,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      Api.fortuneAuspicious,
      idempotencyKey: idempotencyKey,
      data: {
        'occasion': occasion,
        // ส่งหมวดที่ผู้ใช้เลือกไปตรง ๆ — เซิร์ฟเวอร์ใช้ค่านี้ก่อน detect() เสมอ
        // ปล่อยว่างได้ (จะกลับไปเดาจากข้อความเหมือนเดิม)
        'occasion_type': ?occasionType,
        'from_date': ?fromDate,
        'to_date': ?toDate,
      },
    );
    return _readingId(res);
  }

  /// Create a palmistry reading from a palm photo (multipart). The backend
  /// returns 503 (palmistry_unavailable) when no vision model is configured.
  Future<int> createPalmistry({
    required String filePath,
    String? fileName,
    String? question,
    required String idempotencyKey,
  }) async {
    final map = <String, dynamic>{
      'image': await MultipartFile.fromFile(filePath, filename: fileName ?? 'palm.jpg'),
    };
    final q = question?.trim();
    if (q != null && q.isNotEmpty) map['question'] = q;

    final res = await _api.postMultipart<Map<String, dynamic>>(
      Api.fortunePalmistry,
      idempotencyKey: idempotencyKey,
      formData: FormData.fromMap(map),
    );
    return _readingId(res);
  }

  int _readingId(Map<String, dynamic> res) {
    final data = res['data'];
    final id = data is Map ? data['id'] : null;
    if (id is num) return id.toInt();
    throw ApiException(
      statusCode: 500,
      message: 'ไม่ได้รับผลทำนายจากเซิร์ฟเวอร์ กรุณาลองใหม่',
    );
  }
}

/// Container for a single client-side pick — the local TarotCard plus
/// the reversed orientation flipped at reveal time. The repository maps
/// these to the wire payload (`{slug, reversed}`).
class TarotPick {
  const TarotPick({required this.card, this.reversed = false});
  final TarotCard card;
  final bool reversed;
}

/// หมวดงานมงคล — โหลดครั้งเดียวแล้วแคช (ข้อมูลคงที่)
final auspiciousOccasionsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = await ref.watch(fortuneRepositoryProvider.future);
  return repo.occasions();
});

final fortuneRepositoryProvider = FutureProvider<FortuneRepository>((ref) async {
  final api = await ref.watch(apiClientProvider.future);
  return FortuneRepository(api);
});

/// History list provider — used by the home screen "ดูดวงล่าสุดของลูก" section.
final fortuneHistoryProvider = FutureProvider<List<dynamic>>((ref) async {
  final repo = await ref.watch(fortuneRepositoryProvider.future);
  final res = await repo.history();
  return (res['data'] is List) ? res['data'] as List : const [];
});

/// หน้าประวัติ — กรองหมวดที่ **เซิร์ฟเวอร์** ไม่ใช่กรองในเครื่อง
///
/// 🔴 ของเดิมโหลดหน้าแรก 20 รายการแล้วกรองด้วย `.where()` ในเครื่อง ผู้ใช้ที่
/// คุยแชทบ่อย (แต่ละข้อความสร้างแถว type=chat) จะเห็นแต่แชทเต็ม 20 รายการ
/// พอกดชิป "เซลติกครอส" ขึ้น "ยังไม่มีคำทำนายประเภทนี้" ทั้งที่จ่าย ฿99 ไปแล้ว
/// และคำทำนายที่เก่ากว่า 20 รายการเข้าถึงไม่ได้เลยจากในแอพ
///
/// `type = null` = ทุกหมวด
final historyPageProvider =
    FutureProvider.family<HistoryPage, String?>((ref, type) async {
  final repo = await ref.watch(fortuneRepositoryProvider.future);
  final res = await repo.history(type: type);
  return HistoryPage(
    rows: (res['data'] is List) ? res['data'] as List : const [],
    nextCursor: ((res['meta'] as Map?)?['next_cursor'])?.toString(),
  );
});

/// หนึ่งหน้าของประวัติ + เคอร์เซอร์ของหน้าถัดไป (null = หมดแล้ว)
class HistoryPage {
  const HistoryPage({required this.rows, this.nextCursor});
  final List<dynamic> rows;
  final String? nextCursor;
}

/// Single reading detail — keyed by id so multiple opens don't collide.
final readingDetailProvider = FutureProvider.family<Map<String, dynamic>, int>((ref, id) async {
  final repo = await ref.watch(fortuneRepositoryProvider.future);
  return repo.reading(id);
});
