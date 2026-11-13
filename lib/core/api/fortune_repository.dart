import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/data/tarot_deck.dart';
import 'api_client.dart';
import 'api_exceptions.dart';
import 'endpoints.dart';
import '../auth/session.dart';

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

  /// แม่หมออ่านเสร็จหรือยัง → `pending` | `working` | `failed` | `done`
  Future<String> readingStatus(int id) async {
    final res = await _api.get<Map<String, dynamic>>(Api.historyReadingStatus(id));
    final data = res['data'];
    return (data is Map ? data['status']?.toString() : null) ?? 'done';
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
  ///
  /// [voicePremium] — ซื้อเสียงเล่าคำทำนาย + เวลาถามต่อเพิ่ม (สัญญา C1) เซิร์ฟเวอร์ตัดเป็น
  /// รายการที่สองแยกจากค่าไพ่ · 409 `voice_premium_unavailable` = ระบบเสียงปิดอยู่
  /// ยังไม่ตัดอะไรเลย (ทั้งค่าไพ่และค่าเสียง)
  Future<Map<String, dynamic>> createTarotReading({
    required String type,
    String? question,
    required List<TarotPick> picks,
    required String idempotencyKey,
    String? dealToken,
    List<int>? slots,
    String? birthDate,
    bool voicePremium = false,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      Api.historyReadings,
      idempotencyKey: idempotencyKey,
      data: {
        'type': type,
        // 🔮 แม่หมออ่านหลังส่งคำตอบ (แบบเดียวกับเว็บ) — เซิร์ฟเวอร์ตอบ 202 + status pending
        // ทันทีหลังตัดเงิน แล้วหน้าผลถาม [readingStatus] จนเสร็จ ใช้โปรไฟล์ของแพ็กเกจ
        // (อ่านแบบเฉพาะของแต่ละแพ็กเกจ) และซื้อแพ็กเกจยาวได้โดยไม่ชนเพดานคำขอ
        'mode': 'async',
        if (question != null && question.trim().isNotEmpty) 'question': question.trim(),
        'birth_date': ?birthDate,
        // ส่งเฉพาะตอนเลือก — เซิร์ฟเวอร์เก่าไม่รู้จักคีย์นี้ และต้องไม่เห็นค่า false ที่อาจตีความผิด
        if (voicePremium) 'voice_premium': true,
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

/// History list provider — used by the home screen "ดูดวงล่าสุดของคุณ" section.
final fortuneHistoryProvider = FutureProvider<List<dynamic>>((ref) async {
  // ข้อมูลส่วนตัว — ล้างทิ้งเมื่อสลับผู้ใช้ (เดิมอีกคนที่ล็อกอินต่อเห็นคำทำนายของคนก่อน)
  if (ref.watch(sessionUserIdProvider) == null) return const [];
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
  ref.watch(sessionUserIdProvider);
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
  ref.watch(sessionUserIdProvider);
  final repo = await ref.watch(fortuneRepositoryProvider.future);
  return repo.reading(id);
});

// ────────────────────────────────────────────────────────────────────
// ช่องใหม่ของคำทำนาย (docs/API_PARITY_2026-11.md §C2) — ทุกช่องไม่บังคับ
// เซิร์ฟเวอร์เก่าไม่ส่งมา = null/ค่าเริ่มต้น แล้วหน้าจอทำตัวเหมือนแอพ 0.6.0
// ────────────────────────────────────────────────────────────────────

/// ข้อมูลเสริมของคำทำนายหนึ่งรายการ — อ่านจาก map เดียวกับ [readingDetailProvider]
@immutable
class ReadingExtras {
  const ReadingExtras({
    this.persona,
    this.room,
    this.readerName,
    this.premium,
    this.review,
    this.share = const ReadingShare(public: false),
    this.qaMinutes,
    this.voice,
    this.free = false,
  });

  /// ห้องผู้พยากรณ์ที่อ่านไพ่ชุดนี้ (busaba · maemor · kunsai)
  final String? persona;
  final ReadingRoom? room;

  /// "น้องบุษบา" / "แม่หมอ" — ชื่อที่เว็บใช้บนปุ่ม "คุยต่อกับ…"
  final String? readerName;
  final ReadingPremium? premium;
  final ReadingReview? review;
  final ReadingShare share;

  /// ถามต่อในห้องได้กี่นาทีหลังเปิดไพ่ (null = เซิร์ฟเวอร์ไม่บอก/ไม่มีนาฬิกา)
  final int? qaMinutes;

  /// เสียงเล่าที่อัดเสร็จแล้ว (payload.voice) — null = ยังไม่มี/ไม่ได้ซื้อ
  final ReadingVoice? voice;

  /// ไพ่ฟรี 1 ใบ (ธง payload.free — เว็บแยกด้วยธงนี้ ไม่ใช่ราคา)
  final bool free;

  /// ชื่อสั้นสำหรับใช้ในประโยค ("บุษบากำลังอ่านไพ่…") — ไม่รู้ = แม่หมอ
  String get readerShort {
    final s = room?.short;
    if (s != null && s.isNotEmpty) return s;
    return switch (persona) {
      'busaba' => 'บุษบา',
      _ => 'แม่หมอ',
    };
  }

  /// ชื่อเต็มบนปุ่ม/หัวห้อง — ไม่รู้ = แม่หมอ (ข้อความเดิมของแอพ)
  String get readerDisplay {
    final n = readerName;
    if (n != null && n.isNotEmpty) return n;
    return room?.name ?? 'แม่หมอ';
  }

  factory ReadingExtras.fromReading(Map<String, dynamic> r) {
    final payload = r['payload'] is Map ? Map<String, dynamic>.from(r['payload'] as Map) : const <String, dynamic>{};
    final room = r['room'];
    // เซิร์ฟเวอร์เก่าไม่มีคีย์ premium/voice แต่ส่ง payload ดิบมา (status: paid|refunded)
    final premium = r['premium'] is Map ? r['premium'] : payload['premium'];
    final share = r['share'];
    final voice = r['voice'] is Map ? r['voice'] : payload['voice'];
    final persona = _str(r['persona']) ?? _str(room is Map ? room['key'] : null);
    return ReadingExtras(
      persona: persona,
      room: room is Map ? ReadingRoom.fromJson(Map<String, dynamic>.from(room)) : null,
      readerName: _str(r['reader_name']),
      premium: premium is Map ? ReadingPremium.fromJson(Map<String, dynamic>.from(premium)) : null,
      review: r['review'] is Map ? ReadingReview.fromJson(Map<String, dynamic>.from(r['review'] as Map)) : null,
      share: share is Map
          ? ReadingShare.fromJson(Map<String, dynamic>.from(share))
          : ReadingShare(public: r['shared_public'] == true),
      qaMinutes: _positiveInt(r['qa_minutes']),
      voice: voice is Map ? ReadingVoice.fromJson(Map<String, dynamic>.from(voice)) : null,
      free: payload['free'] == true,
    );
  }
}

/// หัวห้องบนหน้าผล — `room {key, name, short, image_url}`
@immutable
class ReadingRoom {
  const ReadingRoom({required this.key, required this.name, required this.short, this.imageUrl});
  final String key;
  final String name;
  final String short;

  /// ภาพผู้พยากรณ์ (https เท่านั้น — อย่างอื่นใช้ภาพในเครื่อง)
  final String? imageUrl;

  factory ReadingRoom.fromJson(Map<String, dynamic> j) => ReadingRoom(
        key: _str(j['key']) ?? 'maemor',
        name: _str(j['name']) ?? 'แม่หมอจันทรา',
        short: _str(j['short']) ?? 'แม่หมอ',
        imageUrl: _https(j['image_url']),
      );
}

/// เสียงพรีเมียมของคำทำนาย — `premium {status, price}`
@immutable
class ReadingPremium {
  const ReadingPremium({required this.status, this.price});

  /// เว็บเก็บ `paid | refunded` · API อาจส่ง `active` — ถือว่าเหมือนกัน
  final String status;
  final num? price;

  bool get active => status == 'paid' || status == 'active';
  bool get refunded => status == 'refunded';

  factory ReadingPremium.fromJson(Map<String, dynamic> j) => ReadingPremium(
        status: _str(j['status']) ?? '',
        price: j['price'] is num ? j['price'] as num : num.tryParse('${j['price']}'),
      );
}

/// รีวิวของลูกค้าต่อคำทำนาย — `review {rating, message, allow_public}`
@immutable
class ReadingReview {
  const ReadingReview({required this.rating, this.message = '', this.allowPublic = false, this.approved, this.name});
  final int rating;
  final String message;
  final bool allowPublic;

  /// แอดมินอนุมัติขึ้นหน้าแรกแล้วไหม (null = เซิร์ฟเวอร์ไม่บอก)
  final bool? approved;

  /// ชื่อที่จะแสดงบนหน้าแรกเว็บ
  final String? name;

  factory ReadingReview.fromJson(Map<String, dynamic> j) => ReadingReview(
        rating: ((j['rating'] as num?)?.toInt() ?? 0).clamp(0, 5),
        message: j['message']?.toString().trim() ?? '',
        allowPublic: j['allow_public'] == true || j['allow_public'] == 1,
        approved: j['approved'] is bool ? j['approved'] as bool : null,
        name: _str(j['name']),
      );
}

/// ลิงก์สาธารณะของคำทำนาย — `share {public, url}`
@immutable
class ReadingShare {
  const ReadingShare({required this.public, this.url});
  final bool public;

  /// ลิงก์ที่เซิร์ฟเวอร์ให้มา (https เท่านั้น) — null = ยังไม่มี/เซิร์ฟเวอร์เก่า
  final String? url;

  factory ReadingShare.fromJson(Map<String, dynamic> j) => ReadingShare(
        public: j['public'] == true,
        url: _https(j['url']),
      );
}

/// เสียงเล่าคำทำนายที่อัดเสร็จ (payload.voice ตามสัญญา 23.2 ของเว็บ)
@immutable
class ReadingVoice {
  const ReadingVoice({required this.status, this.duration, this.chapters = const []});

  /// ready · partial · none
  final String status;
  final double? duration;
  final List<VoiceChapter> chapters;

  bool get playable => status == 'ready' || status == 'partial';

  factory ReadingVoice.fromJson(Map<String, dynamic> j) {
    final raw = j['chapters'];
    return ReadingVoice(
      status: _str(j['status']) ?? 'none',
      duration: (j['duration'] as num?)?.toDouble(),
      chapters: raw is List
          ? raw.whereType<Map>().map((m) => VoiceChapter.fromJson(Map<String, dynamic>.from(m))).toList()
          : const [],
    );
  }
}

/// หนึ่งบทของเสียงเล่า — เวลาเริ่ม/จบในไฟล์รวม + ข้อความที่พูด (ใช้เป็นคำบรรยายใต้ตัวเล่น)
@immutable
class VoiceChapter {
  const VoiceChapter({required this.start, required this.end, this.say = ''});
  final double start;
  final double end;
  final String say;

  factory VoiceChapter.fromJson(Map<String, dynamic> j) => VoiceChapter(
        start: (j['start'] as num?)?.toDouble() ?? 0,
        end: (j['end'] as num?)?.toDouble() ?? 0,
        say: j['say']?.toString() ?? '',
      );
}

String? _str(Object? v) => (v is String && v.trim().isNotEmpty) ? v.trim() : null;

String? _https(Object? v) => (v is String && v.startsWith('https://')) ? v : null;

int? _positiveInt(Object? v) {
  final n = v is num ? v.toInt() : int.tryParse('$v');
  return (n != null && n > 0) ? n : null;
}
