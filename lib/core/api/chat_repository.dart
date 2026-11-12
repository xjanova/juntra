import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'endpoints.dart';
import 'rooms_repository.dart';
import '../auth/session.dart';

/// ห้องคุยกับผู้พยากรณ์ (บุษบา · แม่หมอ · คุณไสย) — wraps /v1/chat/*.
///
/// New conversation flow (juntraweb-side, docs/API_PARITY_2026-11.md §A):
///   1. POST /v1/chat/conversations {reading_id?, room?, new?} → {conversation, balance, cost, …}
///   2. POST /v1/chat/conversations/{id}/send {message}        → {message, reply, offers, qa, …}
///   3. GET  /v1/chat/conversations?room=                      → list past conversations
///   4. GET  /v1/chat/conversations/{id}                       → full history + room state
///   5. POST …/{id}/qa/end · GET …/{id}/feed?after= · GET /v1/chat/live
///
/// All AI calls happen server-side; juntra mobile app holds NO AI keys.
///
/// เซิร์ฟเวอร์เก่า (ก่อนระบบห้อง) ไม่ส่ง persona/room/qa/… — ทุกโมเดลข้างล่างจึงอ่านแบบ
/// "ไม่มี = ห้องแม่หมอ ไม่มีนาฬิกา ไม่มีบิล" เสมอ ห้ามพังเพราะคีย์หาย
class ChatRepository {
  ChatRepository(this._api);
  final ApiClient _api;

  /// เปิดห้อง
  ///
  /// [readingId] = คุยต่อจากคำทำนายไพ่ที่จ่ายแล้ว — ผู้พยากรณ์เห็นไพ่และคำพยากรณ์ชุดนั้นทุกข้อความ
  /// (เซิร์ฟเวอร์คืนห้องเดิมของคำทำนายนั้นถ้าเคยเปิดไว้แล้ว ไม่สร้างห้องซ้ำ)
  ///
  /// [room] = ห้องคุยทั่วไปของผู้พยากรณ์คนนั้น — เซิร์ฟเวอร์คุยต่อห้องล่าสุดให้ เว้นแต่ [startNew]
  /// ⚠️ เซิร์ฟเวอร์เก่าไม่รู้จัก `room` แล้วสร้างห้องแม่หมอใหม่ทุกครั้ง — ส่งเฉพาะเมื่อ
  /// `AppConfig.has('rooms')` (ผู้เรียกเป็นคนเช็ค)
  ///
  /// 422 `room_closed` · 423 `room_locked` (+ `lock`) โยนเป็น [ApiException]
  Future<ChatStart> startConversation({int? readingId, String? room, bool startNew = false}) async {
    final body = <String, dynamic>{
      'reading_id': ?readingId,
      if (readingId == null && room != null) 'room': room,
      if (readingId == null && room != null && startNew) 'new': true,
    };
    final res = await _api.post<Map<String, dynamic>>(
      Api.chatConversations,
      data: body.isEmpty ? null : body,
    );
    return ChatStart.fromJson(_data(res), receivedAt: DateTime.now());
  }

  /// List the user's recent conversations (max 50) — [room] กรองตามห้อง (เซิร์ฟเวอร์เก่าเมินพารามิเตอร์นี้)
  Future<List<ChatConversationSummary>> listConversations({String? room}) async {
    final res = await _api.get<Map<String, dynamic>>(
      Api.chatConversations,
      query: {'room': ?room},
    );
    final list = (res['data'] as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((m) => ChatConversationSummary.fromJson(Map<String, dynamic>.from(m)))
        .where((c) => c.id > 0)
        .toList();
  }

  /// Fetch a full conversation by id (includes all messages + room state).
  Future<ChatConversation> getConversation(int id) async {
    final res = await _api.get<Map<String, dynamic>>(Api.chatConversation(id));
    return ChatConversation.fromJson(_data(res), receivedAt: DateTime.now(), fallbackId: id);
  }

  /// Send a user message.
  ///
  /// On 402 (insufficient funds) / 429 (daily_limit หรือส่งถี่เกินไป) /
  /// 409 (in_flight ข้อความเดิมกำลังส่งอยู่ · busy_other ส่งจากอีกเครื่อง · qa_over หมดเวลาถามต่อ) /
  /// 422 room_closed จะโยน [ApiException] พร้อม reasonCode ให้หน้าจอแยกเคสได้
  ///
  /// [idempotencyKey] ต้องส่งเสมอสำหรับ endpoint นี้เพราะมันตัดเงิน และ
  /// ต้องใช้ค่าเดิมเมื่อผู้ใช้กด "ลองใหม่" ข้อความเดิม (ดู ApiClient.post)
  Future<ChatSendResult> send({
    required int conversationId,
    required String text,
    required String idempotencyKey,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      Api.chatSend(conversationId),
      data: {'message': text},
      idempotencyKey: idempotencyKey,
    );
    return ChatSendResult.fromJson(_data(res), receivedAt: DateTime.now());
  }

  /// "พอแล้ว" — จบเวลาถามต่อก่อนกำหนด (ไม่คิดเงิน · กดซ้ำได้ `message: null`)
  Future<ChatQaEndResult> qaEnd(int conversationId) async {
    final res = await _api.post<Map<String, dynamic>>(Api.chatQaEnd(conversationId));
    return ChatQaEndResult.fromJson(_data(res), receivedAt: DateTime.now());
  }

  /// ข้อความใหม่จากทีมงานหลัง [after] (id ข้อความล่าสุดที่หน้าจอมี)
  Future<ChatFeed> feed(int conversationId, {required int after}) async {
    final res = await _api.get<Map<String, dynamic>>(
      Api.chatFeed(conversationId),
      query: {'after': after},
    );
    return ChatFeed.fromJson(res);
  }

  /// ตัวเลขสดหน้าห้อง (ออนไลน์ · กำลังคุย · คิว) — public
  Future<ChatLiveStats> live() async {
    final res = await _api.get<Map<String, dynamic>>(Api.chatLive);
    return ChatLiveStats.fromJson(_data(res));
  }

  Map<String, dynamic> _data(Map<String, dynamic> res) {
    final inner = res['data'];
    return inner is Map<String, dynamic>
        ? inner
        : inner is Map
            ? Map<String, dynamic>.from(inner)
            : res;
  }
}

/* ══════════════════════ models ══════════════════════ */

int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');
double? _double(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
String? _str(Object? v) => (v is String && v.trim().isNotEmpty) ? v : null;
Map<String, dynamic>? _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : null;

/// ส่วนต่างนาฬิกา = เวลาเซิร์ฟเวอร์ − เวลาเครื่อง ณ ตอนได้คำตอบ
///
/// นาฬิกาถามต่อนับตาม `ends_at` ของเซิร์ฟเวอร์ — เครื่องที่ตั้งเวลาเพี้ยนไป 2 นาที
/// จะเห็นเวลาเหลือผิด 2 นาทีถ้าไม่ชดเชยตรงนี้ (เซิร์ฟเวอร์เก่าไม่ส่ง = ไม่ชดเชย)
Duration clockSkew(Object? serverTime, DateTime receivedAt) {
  final s = _int(serverTime);
  if (s == null || s <= 0) return Duration.zero;
  return Duration(milliseconds: s * 1000 - receivedAt.millisecondsSinceEpoch);
}

/// นาฬิกาถามต่อหลังเปิดไพ่ (`qa` — ReadingQaClock) หรือถามฟรีหลังไพ่ฟรี (`free_ask` — FreeAskClock)
///
/// เวลาทั้งหมดเป็นของเซิร์ฟเวอร์ (epoch วินาที) แอพแค่นับถอยหลังตาม
@immutable
class ChatClock {
  const ChatClock({
    required this.minutes,
    required this.started,
    required this.over,
    required this.left,
    this.endsAt,
    this.ended = false,
    this.warnMinutes = 3,
    this.premium = false,
    this.skew = Duration.zero,
  });

  final int minutes;

  /// เริ่มนับแล้ว (นับจากคำถามแรกของลูกค้า)
  final bool started;

  /// epoch วินาทีของเซิร์ฟเวอร์ — null = ยังไม่เริ่ม
  final int? endsAt;

  /// ลูกค้ากด "พอแล้ว" ไปแล้ว
  final bool ended;

  /// หมดเวลา/จบแล้ว ณ ตอนที่เซิร์ฟเวอร์ตอบ
  final bool over;

  /// วินาทีที่เหลือ ณ ตอนที่เซิร์ฟเวอร์ตอบ
  final int left;

  /// เหลือไม่เกินกี่นาทีถึงขึ้นสีเตือน
  final int warnMinutes;

  /// ซื้อเสียงพรีเมียม — ทุกคำตอบพูดออกเสียง และได้เวลาถามต่อยาวขึ้น
  final bool premium;
  final Duration skew;

  static ChatClock? fromJson(Object? raw, {Duration skew = Duration.zero, int defaultWarn = 3}) {
    final j = _map(raw);
    if (j == null) return null;
    final minutes = _int(j['minutes']) ?? 0;
    if (minutes <= 0) return null;
    final endsAt = _int(j['ends_at']);
    return ChatClock(
      minutes: minutes,
      started: j['started'] == true,
      endsAt: (endsAt != null && endsAt > 0) ? endsAt : null,
      ended: j['ended'] == true,
      over: j['over'] == true,
      left: math.max(0, _int(j['left']) ?? minutes * 60),
      warnMinutes: _int(j['warn']) ?? defaultWarn,
      premium: j['premium'] == true,
      skew: skew,
    );
  }

  /// วินาทีที่เหลือตอนนี้ — ตามนาฬิกาเซิร์ฟเวอร์ (ชดเชย [skew] แล้ว)
  int secondsLeft([DateTime? now]) {
    if (over) return 0;
    final end = endsAt;
    if (!started || end == null) return minutes * 60;
    final serverNowMs = (now ?? DateTime.now()).millisecondsSinceEpoch + skew.inMilliseconds;
    return math.max(0, ((end * 1000 - serverNowMs) / 1000).ceil());
  }

  bool isOver([DateTime? now]) => over || (started && endsAt != null && secondsLeft(now) <= 0);

  /// ใกล้หมด (ขึ้นสีเตือน)
  bool isLow({DateTime? now, int? warnSeconds}) =>
      started && !isOver(now) && secondsLeft(now) <= (warnSeconds ?? warnMinutes * 60);

  /// mm:ss (ชั่วโมงขึ้นไป = h:mm:ss)
  static String format(int seconds) {
    final s = math.max(0, seconds);
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final ss = (s % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '${m.toString().padLeft(2, '0')}:$ss';
  }
}

/// บิลเติมเงินค้างของห้อง (เว็บ "บิลเลขที่ …") — ช่องทาง APK เท่านั้น
/// เซิร์ฟเวอร์ไม่ส่งให้แอพ Play อยู่แล้ว แต่หน้าจอยังต้องกั้นด้วย isPlayChannel ซ้ำอีกชั้น
@immutable
class ChatPendingBill {
  const ChatPendingBill({
    required this.id,
    required this.ref,
    required this.amount,
    required this.payableAmount,
    this.qrPayload,
    this.expiresAt,
    this.hasSlip = false,
    this.blocks = false,
    this.skew = Duration.zero,
  });

  final int id;
  final String ref;
  final double amount;

  /// ยอดที่ต้องโอนจริง (มีเศษสตางค์ไว้จับคู่ SMS ธนาคาร) — ห้ามปัดเศษ
  final double payableAmount;
  final String? qrPayload;

  /// epoch วินาทีของเซิร์ฟเวอร์
  final int? expiresAt;

  /// แนบสลิปแล้ว = ลูกค้าโอนแล้ว รอตรวจ — ห้ามบอกให้โอนอีก
  final bool hasSlip;

  /// บิลนี้ขวางการเปิดไพ่ (เงินในวอลเลตไม่พอเปิดแบบไหนเลย)
  final bool blocks;
  final Duration skew;

  static ChatPendingBill? fromJson(Object? raw, {Duration skew = Duration.zero}) {
    final j = _map(raw);
    if (j == null) return null;
    final id = _int(j['id']);
    if (id == null || id <= 0) return null;
    final payable = _double(j['payable_amount']) ?? _double(j['amount']) ?? 0;
    return ChatPendingBill(
      id: id,
      ref: _str(j['ref'])?.trim() ?? '#$id',
      amount: _double(j['amount']) ?? payable,
      payableAmount: payable,
      qrPayload: _str(j['qr_payload']),
      expiresAt: _int(j['expires_at']),
      hasSlip: j['has_slip'] == true,
      blocks: j['blocks'] == true,
      skew: skew,
    );
  }

  int? secondsLeft([DateTime? now]) {
    final end = expiresAt;
    if (end == null) return null;
    final serverNowMs = (now ?? DateTime.now()).millisecondsSinceEpoch + skew.inMilliseconds;
    return math.max(0, ((end * 1000 - serverNowMs) / 1000).ceil());
  }

  bool isExpired([DateTime? now]) {
    final s = secondsLeft(now);
    return s != null && s <= 0;
  }
}

/// แพ็กเกจที่ผู้พยากรณ์ยื่นในแชท (`offers`) หรือเมนูไพ่ของห้อง (`menu`)
@immutable
class ChatOffer {
  const ChatOffer({
    required this.kind,
    required this.label,
    this.key,
    this.spread,
    this.cards,
    this.price,
    this.blurb,
    this.lockedUntil,
  });

  final String kind; // tarot | deep
  final String label;
  final String? key;
  final String? spread;
  final int? cards;
  final num? price;
  final String? blurb;

  /// ข้อห้ามเปิดซ้ำ — วันที่เปิดได้อีก (ข้อความไทยจากเซิร์ฟเวอร์) · null = เปิดได้เลย
  final String? lockedUntil;

  bool get locked => lockedUntil != null;

  static ChatOffer? fromJson(Object? raw) {
    final m = _map(raw);
    if (m == null) return null;
    final label = _str(m['label']);
    if (label == null) return null;
    final price = m['price'];
    return ChatOffer(
      kind: _str(m['kind']) ?? ((m['spread'] ?? m['key']) == 'deep' ? 'deep' : 'tarot'),
      label: label,
      key: _str(m['key']),
      spread: _str(m['spread']),
      cards: _int(m['cards']),
      price: price is num ? price : num.tryParse('${price ?? ''}'),
      blurb: _str(m['blurb']),
      lockedUntil: _str(m['locked_until']),
    );
  }

  static List<ChatOffer> listFrom(Object? raw) => raw is List
      ? raw.map(ChatOffer.fromJson).whereType<ChatOffer>().toList()
      : const [];
}

/// ปุ่มคำถามลัด (`suggestions` — ChatSuggestions ของเว็บ)
@immutable
class ChatSuggestion {
  const ChatSuggestion({required this.label, required this.prompt, this.icon = '✨'});

  final String label;
  final String prompt;
  final String icon;

  static List<ChatSuggestion> listFrom(Object? raw) => raw is List
      ? [
          for (final m in raw.whereType<Map>())
            if (_str(m['label']) != null && _str(m['prompt']) != null)
              ChatSuggestion(
                label: m['label'].toString(),
                prompt: m['prompt'].toString(),
                icon: _str(m['icon']) ?? '✨',
              ),
        ]
      : const [];
}

/// ห้องย่อของบทสนทนา (`room` ใน conversation/list item)
@immutable
class ChatRoomBrief {
  const ChatRoomBrief({
    required this.key,
    required this.name,
    required this.short,
    required this.accent,
    this.imageUrl,
    this.fromServer = false,
  });

  final String key;
  final String name;
  final String short;
  final Color accent;
  final String? imageUrl;
  final bool fromServer;

  /// อ่านจาก `room` (ถ้ามี) ไม่งั้นจาก `persona` · ไม่มีทั้งคู่ (เซิร์ฟเวอร์เก่า) = ห้องแม่หมอ
  static ChatRoomBrief fromJson(Object? room, {Object? persona}) {
    final j = _map(room);
    final key = OracleRoom.normalize(_str(j?['key']) ?? _str(persona));
    final base = OracleRoom.builtIn(key);
    return ChatRoomBrief(
      key: key,
      name: _str(j?['name']) ?? base.name,
      short: _str(j?['short']) ?? base.short,
      accent: OracleRoom.parseAccent(j?['accent']) ?? base.accent,
      imageUrl: httpsOrNull(j?['image_url']),
      fromServer: j != null,
    );
  }

  /// ห้องในเครื่อง (ใช้กับเซิร์ฟเวอร์เก่า / ก่อนเปิดห้องเสร็จ)
  factory ChatRoomBrief.local(String? key) => ChatRoomBrief.fromJson(null, persona: key);
}

/// ข้อความหนึ่งฟองจากเซิร์ฟเวอร์
@immutable
class ChatMessageDto {
  const ChatMessageDto({
    required this.role,
    required this.content,
    this.id,
    this.fromAdmin = false,
    this.adminAs,
    this.offerTopic,
    this.offers = const [],
    this.createdAt,
  });

  final int? id;
  final String role; // user | assistant
  final String content;
  final bool fromAdmin;

  /// "admin" = ทีมงานพิมพ์ในนามเจ้าหน้าที่ · null = อื่น ๆ (ทีมงานที่ "คุยแทนผู้พยากรณ์" มาเป็น null — ตั้งใจ)
  final String? adminAs;
  final String? offerTopic;
  final List<ChatOffer> offers;
  final DateTime? createdAt;

  bool get fromUser => role == 'user';

  /// ฟองของเจ้าหน้าที่ — วาดป้าย "เจ้าหน้าที่" เฉพาะ admin_as == admin (= from_admin)
  bool get isStaff => !fromUser && (adminAs == 'admin' || fromAdmin);

  static ChatMessageDto? fromJson(Object? raw) {
    final m = _map(raw);
    if (m == null) return null;
    return ChatMessageDto(
      id: _int(m['id']),
      role: m['role'] == 'user' ? 'user' : 'assistant',
      content: m['content']?.toString() ?? '',
      fromAdmin: m['from_admin'] == true,
      adminAs: _str(m['admin_as']),
      offerTopic: _str(m['offer_topic']),
      offers: ChatOffer.listFrom(m['offers']),
      createdAt: DateTime.tryParse('${m['created_at'] ?? ''}'),
    );
  }

  static List<ChatMessageDto> listFrom(Object? raw) => raw is List
      ? raw.map(ChatMessageDto.fromJson).whereType<ChatMessageDto>().toList()
      : const [];
}

/// สถานะห้องที่แนบมากับทุกคำตอบ (นาฬิกา · บิลค้าง · เมนูไพ่) — RoomState ของ API
@immutable
class ChatRoomStatus {
  const ChatRoomStatus({
    this.qa,
    this.freeAsk,
    this.pendingBill,
    this.menu = const [],
    this.skew = Duration.zero,
  });

  /// นาฬิกาถามต่อ — null = ห้องคุยทั่วไป / เซิร์ฟเวอร์เก่า
  final ChatClock? qa;

  /// นาฬิกาถามฟรีหลังไพ่ฟรี — null = ห้องอื่น
  final ChatClock? freeAsk;
  final ChatPendingBill? pendingBill;
  final List<ChatOffer> menu;
  final Duration skew;

  factory ChatRoomStatus.fromJson(Map<String, dynamic> j, {required DateTime receivedAt}) {
    final skew = clockSkew(j['server_time'], receivedAt);
    return ChatRoomStatus(
      qa: ChatClock.fromJson(j['qa'], skew: skew),
      // ถามฟรีเตือนที่ 1 นาทีสุดท้ายเหมือนเว็บ
      freeAsk: ChatClock.fromJson(j['free_ask'], skew: skew, defaultWarn: 1),
      pendingBill: ChatPendingBill.fromJson(j['pending_bill'], skew: skew),
      menu: ChatOffer.listFrom(j['menu']),
      skew: skew,
    );
  }
}

/// โควตา/ราคา/ปุ่มลัด — ช่องที่ไม่มีในคำตอบ = null (ให้หน้าจอคงค่าเดิมไว้ ไม่เดาเอง)
@immutable
class ChatQuota {
  const ChatQuota({
    this.cost,
    this.nextCost,
    this.balance,
    this.dailyLimit,
    this.dailyLeft,
    this.blocked,
    this.awaiting,
    this.suggestions,
    this.aiSuggestions,
  });

  final double? cost;
  final double? nextCost;
  final double? balance;
  final int? dailyLimit;
  final int? dailyLeft;
  final bool? blocked;
  final bool? awaiting;

  /// null = ไม่มีคีย์หรือว่าง (คงชุดเดิม)
  final List<ChatSuggestion>? suggestions;

  /// ปุ่มที่ผู้พยากรณ์คิดมาให้ (ข้อความล้วน) — null = เซิร์ฟเวอร์เก่าไม่ส่งคีย์นี้
  final List<String>? aiSuggestions;

  factory ChatQuota.fromJson(Map<String, dynamic> j) {
    final sugg = ChatSuggestion.listFrom(j['suggestions']);
    final ai = j['ai_suggestions'];
    return ChatQuota(
      cost: _double(j['cost']),
      nextCost: _double(j['next_cost']),
      balance: _double(j['balance']),
      dailyLimit: _int(j['daily_limit']),
      dailyLeft: _int(j['daily_left']),
      blocked: j['blocked'] is bool ? j['blocked'] as bool : null,
      awaiting: j['awaiting'] is bool ? j['awaiting'] as bool : null,
      suggestions: sugg.isEmpty ? null : sugg,
      aiSuggestions: ai is List
          ? ai.whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
          : null,
    );
  }
}

/// บทสนทนาหนึ่งห้อง (start → `conversation` · show → ทั้ง data)
@immutable
class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.room,
    required this.messages,
    required this.status,
    required this.quota,
    this.title,
    this.readingId,
    this.freeReadingId,
    this.personaKnown = false,
    this.held = false,
  });

  final int id;
  final String? title;
  final int? readingId;
  final int? freeReadingId;
  final ChatRoomBrief room;

  /// เซิร์ฟเวอร์บอก persona มาจริง (false = เซิร์ฟเวอร์เก่า → ห้องแม่หมอ)
  final bool personaKnown;
  final List<ChatMessageDto> messages;
  final ChatRoomStatus status;
  final ChatQuota quota;

  /// ทีมงานคุมห้องอยู่ (ส่งมาเมื่อเซิร์ฟเวอร์มีคีย์นี้)
  final bool held;

  String get persona => room.key;

  factory ChatConversation.fromJson(Map<String, dynamic> j,
      {required DateTime receivedAt, int? fallbackId, Map<String, dynamic>? outer}) {
    // start: quota อยู่ชั้นนอก ห้อง/นาฬิกาอยู่ใน conversation · show: อยู่ชั้นเดียวกันหมด
    final quotaSource = {...j, ...?outer};
    return ChatConversation(
      id: _int(j['id']) ?? fallbackId ?? 0,
      title: _str(j['title']),
      readingId: _int(j['reading_id']),
      freeReadingId: _int(j['free_reading_id']),
      room: ChatRoomBrief.fromJson(j['room'], persona: j['persona']),
      personaKnown: _str(j['persona']) != null || j['room'] is Map,
      messages: ChatMessageDto.listFrom(j['messages']),
      status: ChatRoomStatus.fromJson({...?outer, ...j}, receivedAt: receivedAt),
      quota: ChatQuota.fromJson(quotaSource),
      held: j['held'] == true,
    );
  }
}

/// คำตอบของ POST /conversations
@immutable
class ChatStart {
  const ChatStart({required this.conversation});
  final ChatConversation conversation;

  ChatQuota get quota => conversation.quota;

  factory ChatStart.fromJson(Map<String, dynamic> j, {required DateTime receivedAt}) {
    final convo = _map(j['conversation']) ?? const <String, dynamic>{};
    final outer = Map<String, dynamic>.from(j)..remove('conversation');
    return ChatStart(
      conversation: ChatConversation.fromJson(convo, receivedAt: receivedAt, outer: outer),
    );
  }
}

/// คำตอบของ POST …/send
@immutable
class ChatSendResult {
  const ChatSendResult({
    required this.reply,
    required this.kind,
    required this.status,
    required this.quota,
    this.message,
    this.offers = const [],
    this.question,
    this.replyVoiceUrl,
    this.held = false,
    this.degraded = false,
  });

  /// ข้อความของผู้พยากรณ์ที่เก็บในห้อง — null = ไม่ได้คำตอบจริง (ระบบแน่น) หรือทีมงานคุมห้อง
  final ChatMessageDto? message;

  /// ข้อความสำหรับแอพรุ่นเก่า (ต่อรายการแพ็กเกจเป็นตัวอักษรท้ายคำตอบ)
  final String reply;

  /// reply · offer · help · held …
  final String kind;
  final List<ChatOffer> offers;
  final String? question;

  /// เสียงคำตอบ (พรีเมียม) — ต้องโหลดด้วย bearer
  final String? replyVoiceUrl;

  /// ทีมงานคุมห้องอยู่ — ข้อความถึงทีมงานแล้ว คำตอบมาทาง feed (ไม่มีฟองคำตอบจากบอท)
  final bool held;

  /// ไม่ได้คำตอบจริง (ระบบแน่น) — ไม่คิดเงิน ส่งข้อความเดิมใหม่ด้วยคีย์เดิมได้ทันที
  final bool degraded;
  final ChatRoomStatus status;
  final ChatQuota quota;

  factory ChatSendResult.fromJson(Map<String, dynamic> j, {required DateTime receivedAt}) {
    final voice = _map(j['reply_voice']);
    final kind = _str(j['kind']) ?? 'reply';
    return ChatSendResult(
      message: ChatMessageDto.fromJson(j['message']),
      reply: j['reply']?.toString() ?? '',
      kind: kind,
      offers: ChatOffer.listFrom(j['offers']),
      question: _str(j['question']),
      replyVoiceUrl: httpsOrNull(voice?['url']),
      held: j['held'] == true || kind == 'held',
      degraded: j['degraded'] == true,
      status: ChatRoomStatus.fromJson(j, receivedAt: receivedAt),
      quota: ChatQuota.fromJson(j),
    );
  }
}

/// คำตอบของ "พอแล้ว"
@immutable
class ChatQaEndResult {
  const ChatQaEndResult({this.qa, this.message});

  final ChatClock? qa;

  /// คำลา — null เมื่อกดซ้ำ (ไม่มีคำลาซ้ำ)
  final ChatMessageDto? message;

  factory ChatQaEndResult.fromJson(Map<String, dynamic> j, {required DateTime receivedAt}) {
    final skew = clockSkew(j['server_time'], receivedAt);
    return ChatQaEndResult(
      qa: ChatClock.fromJson(j['qa'], skew: skew),
      message: ChatMessageDto.fromJson(j['message']),
    );
  }
}

/// ข้อความใหม่จากทีมงาน (`…/feed`)
@immutable
class ChatFeed {
  const ChatFeed({required this.messages, required this.held});
  final List<ChatMessageDto> messages;
  final bool held;

  factory ChatFeed.fromJson(Map<String, dynamic> body) {
    final meta = _map(body['meta']) ?? const <String, dynamic>{};
    return ChatFeed(
      messages: ChatMessageDto.listFrom(body['data']),
      held: meta['held'] == true || body['held'] == true,
    );
  }
}

/// ตัวเลขสดหน้าห้อง (เว็บ /chat/live)
@immutable
class ChatLiveStats {
  const ChatLiveStats({
    required this.online,
    this.chatting = 0,
    this.queue = 0,
    this.bills,
    this.refreshSeconds = 15,
  });

  final int online;
  final int chatting;
  final int queue;
  final int? bills;

  /// ถามใหม่ทุกกี่วินาที (เซิร์ฟเวอร์ cache ไว้เท่านี้ ถามถี่กว่านี้ก็ได้เลขเดิม)
  final int refreshSeconds;

  factory ChatLiveStats.fromJson(Map<String, dynamic> j) {
    final refresh = _int(j['refresh_seconds']) ?? 15;
    return ChatLiveStats(
      online: math.max(0, _int(j['online']) ?? 0),
      chatting: math.max(0, _int(j['chatting']) ?? 0),
      queue: math.max(0, _int(j['queue']) ?? 0),
      bills: _int(j['bills']),
      // ไม่ถามถี่เกิน 10 วิ แม้เซิร์ฟเวอร์บอกน้อยกว่านั้น · ไม่ห่างเกิน 5 นาที
      refreshSeconds: refresh.clamp(10, 300),
    );
  }
}

/// หนึ่งแถวในรายการบทสนทนา
@immutable
class ChatConversationSummary {
  const ChatConversationSummary({
    required this.id,
    required this.room,
    this.title,
    this.readingId,
    this.freeReadingId,
    this.messageCount = 0,
    this.updatedAt,
  });

  final int id;
  final String? title;
  final int? readingId;
  final int? freeReadingId;
  final int messageCount;
  final DateTime? updatedAt;
  final ChatRoomBrief room;

  factory ChatConversationSummary.fromJson(Map<String, dynamic> j) => ChatConversationSummary(
        id: _int(j['id']) ?? 0,
        title: _str(j['title']),
        readingId: _int(j['reading_id']),
        freeReadingId: _int(j['free_reading_id']),
        messageCount: _int(j['message_count']) ?? 0,
        updatedAt: DateTime.tryParse('${j['updated_at'] ?? ''}')?.toLocal(),
        room: ChatRoomBrief.fromJson(j['room'], persona: j['persona']),
      );
}

/* ══════════════════════ providers ══════════════════════ */

final chatRepositoryProvider = FutureProvider<ChatRepository>((ref) async {
  final api = await ref.watch(apiClientProvider.future);
  return ChatRepository(api);
});

/// Conversation list — feeds ConversationListScreen. Key = ห้องที่กรอง (null = ทุกห้อง)
/// `ref.invalidate(chatConversationsProvider)` ล้างทุกตัวกรองพร้อมกัน — เรียกหลังเปิดห้อง/ส่งข้อความ
final chatConversationsProvider =
    FutureProvider.family<List<ChatConversationSummary>, String?>((ref, room) async {
  ref.watch(sessionUserIdProvider); // ข้อมูลส่วนตัว — ล้างทิ้งเมื่อสลับผู้ใช้
  final repo = await ref.watch(chatRepositoryProvider.future);
  return repo.listConversations(room: room);
});

/// Single conversation detail — keyed by id.
final chatConversationProvider =
    FutureProvider.family<ChatConversation, int>((ref, id) async {
  ref.watch(sessionUserIdProvider);
  final repo = await ref.watch(chatRepositoryProvider.future);
  return repo.getConversation(id);
});

/// ตัวเลขสดหน้าเลือกห้อง — ผู้เรียกเป็นคนสั่งรีเฟรช (invalidate) ตาม refresh_seconds
/// ขณะหน้าจอเปิดอยู่ · ได้ null = ไม่มีบริการนี้ (เซิร์ฟเวอร์เก่า 404) หรือดึงไม่ได้ → ซ่อนป้าย
final chatLiveStatsProvider = FutureProvider.autoDispose<ChatLiveStats?>((ref) async {
  final repo = await ref.watch(chatRepositoryProvider.future);
  try {
    return await repo.live();
  } catch (e) {
    if (kDebugMode) debugPrint('[ChatLive] $e');
    return null;
  }
});
