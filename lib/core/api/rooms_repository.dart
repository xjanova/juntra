import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/session.dart';
import 'api_client.dart';
import 'api_exceptions.dart';
import 'endpoints.dart';

/// ห้องผู้พยากรณ์ 3 ห้องตามหน้า "เลือกผู้พยากรณ์" ของเว็บ (`GET /v1/chat/rooms`)
///
/// key ของห้อง = persona ทั้งระบบ (แชท คำทำนาย เสียงพากย์):
///   busaba (น้องบุษบา — ไพ่ไม่ถึง 10 ใบทั้งหมด) · maemor (แม่หมอจันทรา — Celtic, 12 เดือน)
///   · kunsai (แม่หมอจันทรา · คุณไสย — ไพ่ดูคุณไสย)
///
/// ข้อความในห้อง (eyebrow/title/quote/tags) ก๊อปจาก juntraweb `config/chat_rooms.php`
/// ไว้เป็นสำรองเท่านั้น — ของจริงมาจากเซิร์ฟเวอร์เสมอ
@immutable
class OracleRoom {
  const OracleRoom({
    required this.key,
    required this.name,
    required this.short,
    required this.eyebrow,
    required this.title,
    required this.quote,
    required this.tags,
    required this.accent,
    required this.open,
    required this.spreads,
    this.imageUrl,
    this.product,
    this.media = const RoomMedia(),
    this.fromServer = false,
  });

  static const defaultKey = 'maemor';
  static const keys = ['busaba', 'maemor', 'kunsai'];

  final String key;
  final String name;
  final String short;
  final String eyebrow;
  final String title;
  final String quote;
  final List<String> tags;
  final Color accent;

  /// เปิดให้คุยอยู่ไหม (ปิด = เว็บโชว์ "เร็ว ๆ นี้")
  final bool open;

  /// แพ็กเกจที่ห้องนี้ขายตอนนี้ (แพ็กเกจประจำห้องขึ้นก่อน)
  final List<String> spreads;
  final String? imageUrl;
  final RoomProduct? product;
  final RoomMedia media;
  final bool fromServer;

  /// ภาพห้องในแอพ (ชุดเดียวกับเว็บ — ใช้ตอนไม่มีเน็ต/ก่อนภาพจากเซิร์ฟเวอร์โหลดเสร็จ)
  String get localImage => 'assets/images/rooms/$key.webp';

  /// ภาพแม่หมอเดิม — ทางถอยสุดท้ายของ errorBuilder
  static const fallbackImage = 'assets/images/maehmor.webp';

  /// ค่าแปลก/ไม่มี → ห้องแม่หมอ (เหมือน `ChatRooms::normalize`)
  static String normalize(String? key) =>
      (key != null && keys.contains(key)) ? key : defaultKey;

  /// ห้องสำรองในเครื่องตามคีย์
  static OracleRoom builtIn(String? key) => _builtIn[normalize(key)]!;

  factory OracleRoom.fromJson(Map<String, dynamic> j) {
    final key = normalize(j['key']?.toString());
    final base = _builtIn[key]!;
    String s(String k, String d) {
      final v = j[k];
      return (v is String && v.trim().isNotEmpty) ? v : d;
    }

    final tags = j['tags'] is List
        ? (j['tags'] as List).map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : base.tags;
    final spreads = j['spreads'] is List
        ? (j['spreads'] as List).map((e) => e.toString()).toList()
        : base.spreads;
    final product = j['product'];
    final media = j['media'];
    return OracleRoom(
      key: key,
      name: s('name', base.name),
      short: s('short', base.short),
      eyebrow: s('eyebrow', base.eyebrow),
      title: s('title', base.title),
      quote: s('quote', base.quote),
      tags: tags,
      accent: parseAccent(j['accent']) ?? base.accent,
      open: j['open'] == true,
      spreads: spreads,
      imageUrl: httpsOrNull(j['image_url']),
      product: product is Map ? RoomProduct.fromJson(Map<String, dynamic>.from(product)) : null,
      media: media is Map ? RoomMedia.fromJson(Map<String, dynamic>.from(media)) : const RoomMedia(),
      fromServer: true,
    );
  }

  /// เซิร์ฟเวอร์ส่ง "#7cc7f6" หรือชื่อ (sky · violet · crimson)
  static Color? parseAccent(Object? v) {
    if (v is! String) return null;
    switch (v) {
      case 'sky':
        return const Color(0xFF7CC7F6);
      case 'violet':
        return const Color(0xFFA884F4);
      case 'crimson':
        return const Color(0xFFE0455F);
    }
    final hex = v.replaceFirst('#', '');
    if (hex.length != 6) return null;
    final n = int.tryParse(hex, radix: 16);
    return n == null ? null : Color(0xFF000000 | n);
  }

  static const _builtIn = <String, OracleRoom>{
    'busaba': OracleRoom(
      key: 'busaba',
      name: 'น้องบุษบา',
      short: 'บุษบา',
      eyebrow: 'ศิษย์แม่หมอ · ดูไว ตรงประเด็น',
      title: 'อยากรู้เร็ว ๆ ถามบุษบาได้เลย',
      quote: 'สวัสดีค่า บุษบาเองค่ะ ถามมาตรง ๆ ได้เลยน้า บุษบาตอบไว ไม่อ้อมค้อม',
      tags: ['ไพ่ 1-5 ใบ', 'คำตอบไว', 'สดใสเป็นกันเอง'],
      accent: Color(0xFF7CC7F6),
      open: false,
      spreads: ['quick', 'single', 'three', 'love', 'career', 'decision'],
    ),
    'maemor': OracleRoom(
      key: 'maemor',
      name: 'แม่หมอจันทรา',
      short: 'แม่หมอ',
      eyebrow: 'ผู้พยากรณ์หลัก · ละเอียดทั้งดวง',
      title: 'เล่าให้แม่หมอฟัง แม่หมอดูให้ถึงแก่น',
      quote: 'มานั่งตรงนี้ก่อนนะคะ เล่าให้แม่หมอฟัง แม่หมอจะดูให้ละเอียดทุกด้าน',
      tags: ['Celtic Cross 10 ใบ', '12 เดือน', 'ผสานดวงวันเกิด'],
      accent: Color(0xFFA884F4),
      // ห้องหลักปิดไม่ได้ (ChatRooms::isOpen)
      open: true,
      spreads: ['celtic', 'year'],
    ),
    'kunsai': OracleRoom(
      key: 'kunsai',
      name: 'แม่หมอจันทรา · คุณไสย',
      short: 'แม่หมอ',
      eyebrow: 'ห้องพิธี · ของ คุณไสย สิ่งลี้ลับ',
      title: 'สงสัยโดนของ ให้แม่หมอส่องให้',
      quote: 'ตั้งสติให้มั่น ไพ่บอกตามจริง มีก็ว่ามี ไม่มีก็ว่าไม่มี แม่หมอไม่พูดอ้อม',
      tags: ['ไพ่ดูคุณไสย 10 ใบ', 'ทางแก้ที่ทำเองได้', 'ไม่ขายความกลัว'],
      accent: Color(0xFFE0455F),
      open: false,
      spreads: ['kunsai'],
    ),
  };
}

@immutable
class RoomProduct {
  const RoomProduct({required this.spread, required this.name, required this.cards, this.price});
  final String spread;
  final String name;
  final int cards;
  final num? price;

  factory RoomProduct.fromJson(Map<String, dynamic> j) => RoomProduct(
        spread: j['spread']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        cards: (j['cards'] as num?)?.toInt() ?? 0,
        price: j['price'] is num ? j['price'] as num : num.tryParse('${j['price']}'),
      );
}

/// สื่อของห้อง — คลิป idle (mp4 ทึบ), เพลง, เสียงพากย์ประจำ, ฉากโรงละคร
@immutable
class RoomMedia {
  const RoomMedia({
    this.stillUrl,
    this.loops = const [],
    this.music = const [],
    this.voice = const {},
    this.voiceBySpread = const {},
    this.plateUrl,
    this.spriteUrl,
    this.bgUrl,
  });

  final String? stillUrl;
  final List<String> loops;
  final List<String> music;
  final Map<String, String> voice;
  final Map<String, Map<String, String>> voiceBySpread;
  final String? plateUrl;
  final String? spriteUrl;
  final String? bgUrl;

  /// เสียงประโยค [key] สำหรับแบบไพ่ [spread] (ประโยคเฉพาะแบบมาก่อน — เหมือน OracleMedia::voice)
  String? voiceFor(String key, {String? spread}) {
    final bySpread = spread == null ? null : voiceBySpread[spread];
    return bySpread?[key] ?? voice[key];
  }

  factory RoomMedia.fromJson(Map<String, dynamic> j) {
    List<String> urls(Object? v) => v is List
        ? v.map(httpsOrNull).whereType<String>().toList()
        : const [];
    Map<String, String> urlMap(Object? v) {
      final out = <String, String>{};
      if (v is Map) {
        for (final e in v.entries) {
          final url = httpsOrNull(e.value);
          if (url != null) out[e.key.toString()] = url;
        }
      }
      return out;
    }
    final theater = j['theater'] is Map ? Map<String, dynamic>.from(j['theater'] as Map) : const {};
    final bySpread = j['voice_by_spread'];
    return RoomMedia(
      stillUrl: httpsOrNull(j['still_url']),
      // เล่นได้เฉพาะ mp4 (H.264) — webm alpha วาดในแอพไม่ได้
      loops: urls(j['loops']).where((u) => u.toLowerCase().contains('.mp4')).toList(),
      music: urls(j['music']),
      voice: urlMap(j['voice']),
      voiceBySpread: {
        if (bySpread is Map)
          for (final e in bySpread.entries) e.key.toString(): urlMap(e.value),
      },
      plateUrl: httpsOrNull(theater['plate_url']),
      spriteUrl: httpsOrNull(theater['sprite_url']),
      bgUrl: httpsOrNull(theater['bg_url']),
    );
  }
}

/// ล็อกห้องระหว่างทำนาย (`ReadingRoomLock`) — เปลี่ยนไปห้องอื่นไม่ได้จนกว่าจะจบ
@immutable
class RoomLock {
  const RoomLock({required this.room, required this.until, required this.reason, this.readingId, this.message});
  final String room;
  final DateTime until;

  /// pick (กำลังเลือกไพ่) · reading (กำลังอ่านไพ่) · qa (เวลาถามต่อเดินอยู่)
  final String reason;
  final int? readingId;
  final String? message;

  bool get active => until.isAfter(DateTime.now());

  static RoomLock? fromJson(Object? v) {
    if (v is! Map) return null;
    final until = (v['until'] as num?)?.toInt();
    if (until == null) return null;
    return RoomLock(
      room: OracleRoom.normalize(v['room']?.toString()),
      until: DateTime.fromMillisecondsSinceEpoch(until * 1000),
      reason: v['reason']?.toString() ?? 'reading',
      readingId: (v['reading_id'] as num?)?.toInt(),
      message: v['message']?.toString(),
    );
  }
}

/// ผลของ `GET /v1/chat/rooms` + meta ของหน้าเลือกห้อง
@immutable
class RoomsState {
  const RoomsState({
    required this.rooms,
    this.chatCost,
    this.dailyLimit,
    this.freeDaily = false,
    this.lede,
    this.aiDisclosure,
    this.lock,
    this.fromServer = false,
  });

  /// เซิร์ฟเวอร์เก่า (ไม่มีระบบห้อง) — ห้องแม่หมอห้องเดียว เหมือนแอพ 0.6.0
  static final legacy = RoomsState(rooms: [OracleRoom.builtIn(OracleRoom.defaultKey)]);

  final List<OracleRoom> rooms;
  final num? chatCost;
  final int? dailyLimit;
  final bool freeDaily;
  final String? lede;
  final String? aiDisclosure;
  final RoomLock? lock;
  final bool fromServer;

  List<OracleRoom> get openRooms => rooms.where((r) => r.open).toList();

  /// มีให้เลือกมากกว่าหนึ่งห้อง → โชว์หน้าเลือกผู้พยากรณ์ (ห้องเดียว = เข้าห้องแม่หมอเลย เหมือนเว็บ)
  bool get hasPicker => openRooms.length > 1;

  OracleRoom room(String? key) {
    final k = OracleRoom.normalize(key);
    for (final r in rooms) {
      if (r.key == k) return r;
    }
    return OracleRoom.builtIn(k);
  }

  factory RoomsState.fromJson(Map<String, dynamic> body) {
    final data = body['data'];
    final meta = body['meta'] is Map ? Map<String, dynamic>.from(body['meta'] as Map) : const <String, dynamic>{};
    final rooms = data is List
        ? data.whereType<Map>().map((m) => OracleRoom.fromJson(Map<String, dynamic>.from(m))).toList()
        : <OracleRoom>[];
    return RoomsState(
      rooms: rooms.isEmpty ? legacy.rooms : rooms,
      chatCost: meta['chat_cost'] is num ? meta['chat_cost'] as num : null,
      dailyLimit: (meta['daily_limit'] as num?)?.toInt(),
      freeDaily: meta['free_daily'] == true,
      lede: meta['lede'] is String ? meta['lede'] as String : null,
      aiDisclosure: meta['ai_disclosure'] is String ? meta['ai_disclosure'] as String : null,
      lock: RoomLock.fromJson(meta['lock']),
      fromServer: rooms.isNotEmpty,
    );
  }
}

String? httpsOrNull(Object? v) =>
    (v is String && v.startsWith('https://')) ? v : null;

class RoomsRepository {
  RoomsRepository(this._api);
  final ApiClient _api;

  static const _kCacheKey = 'juntra_chat_rooms_v1';

  Future<RoomsState> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final res = await _api.get<Map<String, dynamic>>(Api.chatRooms);
      final state = RoomsState.fromJson(res);
      if (state.fromServer) {
        // ล็อกห้องเป็นของผู้ใช้ — ไม่เก็บลงแคช
        await prefs.setString(_kCacheKey, jsonEncode({'data': res['data'], 'meta': {...?(res['meta'] as Map?), 'lock': null}}));
      }
      return state;
    } on ApiException catch (e) {
      // เซิร์ฟเวอร์รุ่นก่อนห้อง → ห้องแม่หมอห้องเดียว (ไม่ใช่แคชเก่าที่อาจมีห้องที่ปิดไปแล้ว)
      if (e.statusCode == 404) return RoomsState.legacy;
      if (kDebugMode) debugPrint('[Rooms] live load failed: $e');
    } catch (e) {
      if (kDebugMode) debugPrint('[Rooms] live load failed: $e');
    }
    final cached = prefs.getString(_kCacheKey);
    if (cached != null) {
      try {
        return RoomsState.fromJson(Map<String, dynamic>.from(jsonDecode(cached) as Map));
      } catch (_) {/* cache เสีย */}
    }
    return RoomsState.legacy;
  }
}

/// ห้องทั้งหมด — ผูกกับผู้ใช้ที่ล็อกอิน เพราะ `meta.lock` เป็นของแต่ละคน
final roomsProvider = FutureProvider<RoomsState>((ref) async {
  ref.watch(sessionUserIdProvider);
  final api = await ref.watch(apiClientProvider.future);
  return RoomsRepository(api).load();
});

/// ค่าที่วาดได้ทันที (ยังโหลดอยู่ = ห้องแม่หมอห้องเดียว)
final roomsValueProvider = Provider<RoomsState>((ref) {
  return ref.watch(roomsProvider).valueOrNull ?? RoomsState.legacy;
});
