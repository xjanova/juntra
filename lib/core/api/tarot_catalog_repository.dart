import 'dart:convert';

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
  const CardArt({required this.slug, this.imageUrl});
  final String slug;
  final String? imageUrl;
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
  });

  final Map<String, CardArt> bySlug;
  final String? cardBackUrl;
  final String? version;

  static const empty = TarotCatalog(bySlug: {});

  bool get isEmpty => bySlug.isEmpty;

  /// Web face-image URL for a card [slug], or `null` to fall back to the
  /// local [CardFront] drawing.
  String? faceUrlFor(String? slug) {
    if (slug == null || slug.isEmpty) return null;
    return bySlug[slug]?.imageUrl;
  }
}

/// Loads + caches the tarot art catalog. Cached-first and never throws: the
/// worst case is [TarotCatalog.empty] and the deck draws itself, so a flaky
/// network can never break the cinematic.
class TarotCatalogRepository {
  TarotCatalogRepository(this._api);
  final ApiClient _api;

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
      return TarotCatalog.empty;
    }
  }

  TarotCatalog _parse(Map<String, dynamic> json) {
    final list = (json['data'] is List) ? json['data'] as List : const [];
    final bySlug = <String, CardArt>{};
    for (final item in list) {
      if (item is! Map) continue;
      final slug = item['slug']?.toString();
      if (slug == null || slug.isEmpty) continue;
      final url = item['image_url']?.toString();
      bySlug[slug] = CardArt(
        slug: slug,
        imageUrl: (url != null && url.isNotEmpty) ? url : null,
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
