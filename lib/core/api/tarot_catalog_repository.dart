import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'endpoints.dart';

/// One card's web-served art, keyed by the stable backend [slug].
///
/// [imageUrl] is `null` when juntraweb has no real face image for this card
/// yet — the UI then renders the app's built-in programmatic card face as
/// the fallback (exactly what the seeker asked for: web art when it exists,
/// the existing drawing otherwise).
@immutable
class CardArt {
  const CardArt({required this.slug, this.imageUrl, this.nameTh});
  final String slug;
  final String? imageUrl;

  /// ชื่อไทยจากฐานข้อมูลของเว็บ — **แหล่งเดียวของความจริง**
  ///
  /// 🔴 สำรับในแอพเก็บชื่อไทยของตัวเองไว้ ซึ่งต่างจาก TarotCardSeeder ถึง
  /// 63/78 ใบ (เมเจอร์ 7 ใบ + ไมเนอร์ทั้ง 56 ใบ เช่น 'ถ้วยสอง' vs 'สองถ้วย')
  /// ผู้ใช้จึงเห็นไพ่ใบเดียวถูกเรียกสองชื่อในรอบเดียว — จอเผยไพ่ใช้ชื่อของแอพ
  /// แล้วหน้าผลที่เพิ่งจ่ายเงินใช้ชื่อจากเซิร์ฟเวอร์
  final String? nameTh;
}

/// The full card-art catalog pulled from จันทรา.online (`GET /v1/tarot/cards`),
/// plus the global card-back image. Falls back to [empty] (→ the whole deck
/// renders with the local drawing) when the network is unreachable and there
/// is nothing cached on-device.
@immutable
class TarotCatalog {
  const TarotCatalog({
    required this.bySlug,
    this.cardBackUrl,
    this.version,
    this.error,
  });

  final Map<String, CardArt> bySlug;
  final String? cardBackUrl;
  final String? version;

  /// Short reason the live fetch failed (only set when [bySlug] is empty and
  /// nothing was cached) — surfaced in Settings → "ภาพไพ่จากเว็บ" so a stuck
  /// device reports the actual failure (e.g. `connectionError`, `HTTP 404`).
  final String? error;

  static const empty = TarotCatalog(bySlug: {});

  bool get isEmpty => bySlug.isEmpty;

  /// Web face-image URL for a card [slug], or `null` to fall back to the
  /// local [CardFront] drawing.
  String? faceUrlFor(String? slug) {
    if (slug == null || slug.isEmpty) return null;
    return bySlug[slug]?.imageUrl;
  }

  /// ชื่อไทยของไพ่ตามฐานข้อมูลเว็บ — ใช้ค่านี้ก่อนชื่อในสำรับของแอพเสมอ
  /// เพื่อไม่ให้ไพ่ใบเดียวมีสองชื่อระหว่างจอเผยไพ่กับหน้าผลทำนาย
  String? nameThFor(String? slug) {
    if (slug == null || slug.isEmpty) return null;
    return bySlug[slug]?.nameTh;
  }
}

/// Loads + caches the tarot art catalog. Cached-first and never throws: the
/// worst case is [TarotCatalog.empty] and the deck draws itself, so a flaky
/// network can never break the cinematic.
class TarotCatalogRepository {
  TarotCatalogRepository(this._api);
  final ApiClient _api;

  /// เปิดให้ extension เรียกได้ (การแจกไพ่ใช้ client ตัวเดียวกัน)
  ApiClient get api => _api;

  /// Bump the suffix if the cached envelope shape ever changes.
  static const _cacheKey = 'juntra_tarot_catalog_v1';

  Future<TarotCatalog> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      // Public endpoint — works for guests too (bearer attached only if present).
      final res = await _api.get<Map<String, dynamic>>(Api.tarotCards);
      final catalog = _parse(res);
      // Persist the raw envelope so next cold start has art even offline.
      await prefs.setString(_cacheKey, jsonEncode(res));
      return catalog;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Tarot catalog fetch failed, using on-device cache: $e');
      }
      final cached = prefs.getString(_cacheKey);
      if (cached != null) {
        try {
          return _parse(jsonDecode(cached) as Map<String, dynamic>);
        } catch (_) {
          /* corrupt cache — fall through to empty */
        }
      }
      // Empty + no cache: carry a short failure reason for the diagnostic row.
      return TarotCatalog(bySlug: const {}, error: _shortError(e));
    }
  }

  /// Compact, human-readable failure reason for the Settings diagnostic.
  String _shortError(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      if (code != null) return 'HTTP $code';
      return e.type.name; // connectionError / connectionTimeout / ...
    }
    return e.runtimeType.toString();
  }

  TarotCatalog _parse(Map<String, dynamic> json) {
    final list = (json['data'] is List) ? json['data'] as List : const [];
    final bySlug = <String, CardArt>{};
    for (final item in list) {
      if (item is! Map) continue;
      final slug = item['slug']?.toString();
      if (slug == null || slug.isEmpty) continue;
      final url = item['image_url']?.toString();
      final nameTh = item['name_th']?.toString();
      bySlug[slug] = CardArt(
        slug: slug,
        imageUrl: (url != null && url.isNotEmpty) ? url : null,
        nameTh: (nameTh != null && nameTh.isNotEmpty) ? nameTh : null,
      );
    }
    final back = json['card_back_url']?.toString();
    return TarotCatalog(
      bySlug: bySlug,
      cardBackUrl: (back != null && back.isNotEmpty) ? back : null,
      version: json['version']?.toString(),
    );
  }
}

final tarotCatalogRepositoryProvider =
    FutureProvider<TarotCatalogRepository>((ref) async {
  final api = await ref.watch(apiClientProvider.future);
  return TarotCatalogRepository(api);
});

/// App-wide tarot art catalog. Loaded cached-first and shared by the shuffle
/// cinematic + reading screens. Deliberately NOT kept alive: if the very first
/// load happened while จันทรา.online was briefly unreachable (→ empty catalog),
/// the shuffle screen invalidates this provider so a fresh game re-fetches the
/// real art — the seeker never has to force-close the app to recover.
final tarotCatalogProvider = FutureProvider<TarotCatalog>((ref) async {
  final repo = await ref.watch(tarotCatalogRepositoryProvider.future);
  return repo.load();
});


/// กองไพ่ที่เซิร์ฟเวอร์สับให้ต่อหนึ่งเกม
///
/// 🔴 ทำไมต้องมี: สำรับในแอพเป็น `const` เรียง id 0–77 ตายตัว และซีน "สับไพ่"
/// เป็นแอนิเมชันล้วน ไม่เคยแตะโครงสร้างกอง → ช่องซ้ายบนสุดคือ The Fool
/// ตลอดกาล ผู้ใช้ที่เปิดไพ่สองครั้งแล้วแตะตำแหน่งเดิมได้ไพ่ชุดเดิมเป๊ะ
/// ขณะที่เว็บสับจริงทุกครั้งด้วย `inRandomOrder()`
///
/// หัวตั้ง/หัวกลับก็มาจากที่นี่ (เซิร์ฟเวอร์สุ่ม 50% เท่าเว็บ) แทนที่จะให้
/// แอพสุ่มเอง 30% แล้วส่งขึ้นไปให้เชื่อ
class TarotDeal {
  const TarotDeal({required this.token, required this.cards});

  final String token;

  /// 78 ใบตามลำดับที่สับแล้ว — index = ช่องบนพัดไพ่
  final List<DealCard> cards;
}

class DealCard {
  const DealCard({required this.slug, required this.reversed, this.nameTh});
  final String slug;
  final bool reversed;
  final String? nameTh;
}

extension TarotDealApi on TarotCatalogRepository {
  Future<TarotDeal?> deal() async {
    final res = await api.post<Map<String, dynamic>>(Api.tarotDeal);
    final data = res['data'];
    if (data is! Map) return null;
    final token = data['deal_token']?.toString();
    final raw = data['cards'];
    if (token == null || raw is! List) return null;
    return TarotDeal(
      token: token,
      cards: raw.whereType<Map>().map((c) => DealCard(
            slug: c['slug']?.toString() ?? '',
            reversed: c['reversed'] == true,
            nameTh: c['name_th']?.toString(),
          )).toList(),
    );
  }
}
