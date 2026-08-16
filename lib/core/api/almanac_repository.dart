import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'endpoints.dart';

/// ปฏิทินโหรของวันนี้ — `/v1/almanac/today` (ฟรี ไม่ต้องล็อกอิน)
///
/// มีไว้แทนสองอย่างที่หน้าแรกเคยพิมพ์ตายไว้ในโค้ด:
///
/// - บรรทัด "พระจันทร์ขึ้นกุมราศีกรกฎ — ลูกจะรู้สึกอ่อนไหว…" ซึ่งเป็น
///   **ข้อความคงที่** ทุกคนเห็นเหมือนกันทุกวัน ทั้งที่จันทร์ย้ายราศีทุก ~2.3 วัน
/// - ไพ่ประจำวันที่ตรึงไว้ที่ `tarotDeck[18]` (The Moon) ตลอดกาล
///
/// ค่าทุกตัวคำนวณที่เซิร์ฟเวอร์ด้วย `App\Support\ThaiAstro` ตัวเดียวกับที่
/// หน้าฤกษ์ยามและดวงรายวันของเว็บใช้ — แอพไม่คำนวณดาราศาสตร์ซ้ำเอง
/// (กฎเหล็กข้อ 1 ของโปรเจกต์)
class AlmanacRepository {
  AlmanacRepository(this._api);
  final ApiClient _api;

  Future<Almanac?> today() async {
    final res = await _api.get<Map<String, dynamic>>(Api.almanacToday);
    final data = res['data'];
    if (data is! Map) return null;
    return Almanac.fromJson(Map<String, dynamic>.from(data));
  }
}

/// ปฏิทินโหรหนึ่งวัน — เก็บเฉพาะช่องที่ UI ใช้จริง
class Almanac {
  const Almanac({
    required this.date,
    required this.weekdayTh,
    required this.headline,
    required this.note,
    required this.tithiLabel,
    required this.illumination,
    required this.waxing,
    required this.isHolyDay,
    this.moonSignTh,
    this.moonSignSlug,
    this.yamName,
    this.dailyCardSlug,
    this.dailyCardNameTh,
    this.dailyCardNameEn,
    this.dailyCardImageUrl,
  });

  final String date;
  final String weekdayTh;

  /// เช่น "จันทร์เสวยราศีกรกฎ · ขึ้น ๔ ค่ำ"
  final String headline;
  final String note;
  final String tithiLabel;

  /// 0.0–1.0 — ใช้วาดเสี้ยวจันทร์ให้ตรงกับดิถีจริง
  final double illumination;
  final bool waxing;
  final bool isHolyDay;

  final String? moonSignTh;
  final String? moonSignSlug;
  final String? yamName;

  final String? dailyCardSlug;
  final String? dailyCardNameTh;
  final String? dailyCardNameEn;
  final String? dailyCardImageUrl;

  factory Almanac.fromJson(Map<String, dynamic> j) {
    final tithi = (j['tithi'] as Map?)?.cast<String, dynamic>() ?? const {};
    final moon = (j['moon'] as Map?)?.cast<String, dynamic>() ?? const {};
    final yam = (j['yam'] as Map?)?.cast<String, dynamic>() ?? const {};
    final card = (j['daily_card'] as Map?)?.cast<String, dynamic>();

    return Almanac(
      date: j['date']?.toString() ?? '',
      weekdayTh: j['weekday_th']?.toString() ?? '',
      headline: j['headline']?.toString() ?? '',
      note: j['note']?.toString() ?? '',
      tithiLabel: tithi['label']?.toString() ?? '',
      illumination: (tithi['illumination'] as num?)?.toDouble() ?? 0.0,
      waxing: tithi['side']?.toString() == 'waxing',
      isHolyDay: tithi['is_holy'] == true,
      moonSignTh: moon['name_th']?.toString(),
      moonSignSlug: moon['slug']?.toString(),
      yamName: yam['name']?.toString(),
      dailyCardSlug: card?['slug']?.toString(),
      dailyCardNameTh: card?['name_th']?.toString(),
      dailyCardNameEn: card?['name_en']?.toString(),
      dailyCardImageUrl: card?['image_url']?.toString(),
    );
  }
}

final almanacRepositoryProvider = FutureProvider<AlmanacRepository>((ref) async {
  final api = await ref.watch(apiClientProvider.future);
  return AlmanacRepository(api);
});

/// ปฏิทินของวันนี้ — หน้าแรกอ่านตัวนี้ตัวเดียว
final almanacTodayProvider = FutureProvider<Almanac?>((ref) async {
  final repo = await ref.watch(almanacRepositoryProvider.future);
  return repo.today();
});
