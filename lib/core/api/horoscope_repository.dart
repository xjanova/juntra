import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'endpoints.dart';

/// Daily horoscope — free, read-only `/v1/horoscope*`. Replaces the app's
/// previously-hardcoded "ดวงรายวัน" with the backend's AI-generated content.
class HoroscopeRepository {
  HoroscopeRepository(this._api);
  final ApiClient _api;

  Future<List<Map<String, dynamic>>> signs() async {
    final res = await _api.get<Map<String, dynamic>>(Api.horoscopeIndex);
    final data = res['data'];
    return data is List
        ? data.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
        : const [];
  }

  /// ปีนักษัตร 12 ปี + ปีนักษัตรของปีปัจจุบัน (คำนวณที่เซิร์ฟเวอร์)
  Future<ThaiZodiacInfo> thaiZodiac() async {
    final res = await _api.get<Map<String, dynamic>>(Api.horoscopeThaiZodiac);
    final data = res['data'];
    if (data is! Map) return const ThaiZodiacInfo(year: 0, signs: []);
    final signs = data['signs'];
    return ThaiZodiacInfo(
      year: (data['year'] as num?)?.toInt() ?? 0,
      currentSlug: data['current_slug']?.toString(),
      signs: signs is List
          ? signs.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
          : const [],
    );
  }

  Future<Map<String, dynamic>> daily(String slug) async {
    final res = await _api.get<Map<String, dynamic>>(Api.horoscope(slug));
    final data = res['data'];
    return data is Map<String, dynamic> ? data : const {};
  }
}

/// ปีนักษัตร — ข้อมูลคงที่ โหลดครั้งเดียวแล้วแคช
class ThaiZodiacInfo {
  const ThaiZodiacInfo({required this.year, required this.signs, this.currentSlug});
  final int year;
  final String? currentSlug;
  final List<Map<String, dynamic>> signs;
}

final thaiZodiacProvider = FutureProvider<ThaiZodiacInfo>((ref) async {
  final repo = await ref.watch(horoscopeRepositoryProvider.future);
  return repo.thaiZodiac();
});

final horoscopeRepositoryProvider = FutureProvider<HoroscopeRepository>((ref) async {
  final api = await ref.watch(apiClientProvider.future);
  return HoroscopeRepository(api);
});

final horoscopeSignsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = await ref.watch(horoscopeRepositoryProvider.future);
  return repo.signs();
});

/// `.autoDispose` เพราะดวงเป็นของ "วันนี้" — ถ้าแคชค้างข้ามเที่ยงคืน ผู้ใช้จะ
/// อ่านดวงเมื่อวานต่อโดยไม่มีอะไรบอก (หน้าจอมีวันที่กำกับแล้ว แต่ค่าต้องสดด้วย)
final dailyHoroscopeProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, slug) async {
  final repo = await ref.watch(horoscopeRepositoryProvider.future);
  return repo.daily(slug);
});
