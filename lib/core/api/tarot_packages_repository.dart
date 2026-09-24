import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/data/spreads.dart';
import 'api_client.dart';
import 'endpoints.dart';

/// แพ็กเกจไพ่หนึ่งแบบ — ชุดเดียวกับหน้า /tarot บนเว็บ (`GET /v1/tarot/packages`)
///
/// เดิมแอพเก็บรายการแพ็กเกจของตัวเองไว้ใน `spreads.dart` แล้วเดาราคาจาก `/wallet`
/// แพ็กเกจใหม่ (คุณไสย) ภาพประกอบประจำแพ็กเกจ ข้อห้ามเปิดซ้ำ และช่องวันเกิด
/// ไปไม่ถึงแอพจนกว่าจะออกรุ่นใหม่ — ตอนนี้มาจากเซิร์ฟเวอร์ทั้งหมด
/// `spreads.dart` เหลือเป็นแค่สำรองตอนออฟไลน์
@immutable
class TarotPackage {
  const TarotPackage({
    required this.key,
    required this.nameTh,
    required this.cards,
    required this.positions,
    this.nameEn,
    this.eyebrow,
    this.tagline,
    this.layout = 'grid',
    this.est,
    this.price,
    this.free = false,
    this.birth = false,
    this.cooldownDays = 0,
    this.requiresAsync = false,
    this.imageUrl,
    this.fromServer = true,
  });

  /// คีย์ของเซิร์ฟเวอร์ (single · three · love · … · kunsai) — type = `tarot_<key>`
  final String key;
  final String nameTh;
  final String? nameEn;
  final String? eyebrow;
  final String? tagline;
  final String layout;
  final String? est;
  final int cards;
  final List<String> positions;

  /// ราคาจริงจากหลังบ้าน (null = ไม่รู้ — ออฟไลน์และไม่มีแคช)
  final num? price;
  final bool free;

  /// แพ็กเกจที่ผสานดวงวันเกิด (Celtic · 12 เดือน · คุณไสย) — ถามวันเกิดแบบไม่บังคับ
  final bool birth;

  /// ข้อห้ามของครูบาอาจารย์: เปิดแพ็กเกจเดิมซ้ำไม่ได้ภายใน N วัน (0 = ไม่จำกัด)
  final int cooldownDays;
  final bool requiresAsync;
  final String? imageUrl;
  final bool fromServer;

  String get type => 'tarot_$key';

  factory TarotPackage.fromJson(Map<String, dynamic> j) {
    final positions = (j['positions'] is List)
        ? (j['positions'] as List).map((e) => e.toString()).toList()
        : const <String>[];
    return TarotPackage(
      key: j['key'].toString(),
      nameTh: j['name_th']?.toString() ?? j['key'].toString(),
      nameEn: j['name_en']?.toString(),
      eyebrow: j['eyebrow']?.toString(),
      tagline: j['tagline']?.toString(),
      layout: j['layout']?.toString() ?? 'grid',
      est: j['est']?.toString(),
      cards: (j['cards'] as num?)?.toInt() ?? positions.length,
      positions: positions,
      price: j['price'] is num ? j['price'] as num : num.tryParse('${j['price']}'),
      free: j['free'] == true,
      birth: j['birth'] == true,
      cooldownDays: (j['cooldown_days'] as num?)?.toInt() ?? 0,
      requiresAsync: j['requires_async'] == true,
      imageUrl: (j['image_url']?.toString().startsWith('https://') ?? false)
          ? j['image_url'].toString()
          : null,
    );
  }

  /// สำรองตอนออฟไลน์ครั้งแรก — ราคาไม่รู้ (ไม่เอาราคาที่ฝังไว้มาโชว์ให้ผิด)
  factory TarotPackage.fromLocal(Spread s) => TarotPackage(
        key: s.id,
        nameTh: s.name,
        tagline: s.desc,
        eyebrow: '${s.cards} ใบ',
        cards: s.cards,
        positions: s.positions,
        layout: s.id == 'celtic' ? 'celtic' : 'grid',
        birth: s.id == 'celtic' || s.id == 'year',
        fromServer: false,
      );
}

class TarotPackagesRepository {
  TarotPackagesRepository(this._api);
  final ApiClient _api;

  static const _kCacheKey = 'juntra_tarot_packages_v1';

  Future<List<TarotPackage>> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final res = await _api.get<Map<String, dynamic>>(Api.tarotPackages);
      final data = res['data'];
      if (data is List && data.isNotEmpty) {
        await prefs.setString(_kCacheKey, jsonEncode(data));
        return _parse(data);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[TarotPackages] live load failed: $e');
    }
    final cached = prefs.getString(_kCacheKey);
    if (cached != null) {
      try {
        final list = _parse(jsonDecode(cached) as List);
        if (list.isNotEmpty) return list;
      } catch (_) {/* cache เสีย */}
    }
    return spreads.map(TarotPackage.fromLocal).toList();
  }

  List<TarotPackage> _parse(List data) => data
      .whereType<Map>()
      .map((m) => TarotPackage.fromJson(Map<String, dynamic>.from(m)))
      .where((p) => p.key.isNotEmpty && p.cards > 0 && p.positions.length == p.cards)
      .toList();
}

final tarotPackagesProvider = FutureProvider<List<TarotPackage>>((ref) async {
  final api = await ref.watch(apiClientProvider.future);
  return TarotPackagesRepository(api).load();
});

/// แพ็กเกจตามคีย์ — null ถ้าปิดขายไปแล้ว/ไม่รู้จัก
final tarotPackageProvider = FutureProvider.family<TarotPackage?, String>((ref, key) async {
  final all = await ref.watch(tarotPackagesProvider.future);
  for (final p in all) {
    if (p.key == key) return p;
  }
  return null;
});
