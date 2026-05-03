import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'endpoints.dart';

/// Thin wrapper around the /v1/fortune/* endpoints.
///
/// Backed by the Laravel `FortuneAIService` pool — see
/// `backend-patches/juntra/` for the controllers this calls.
class FortuneRepository {
  FortuneRepository(this._api);
  final ApiClient _api;

  Future<Map<String, dynamic>> categories() async {
    return _api.get<Map<String, dynamic>>(Api.fortuneCategories);
  }

  Future<Map<String, dynamic>> spreads() async {
    return _api.get<Map<String, dynamic>>(Api.fortuneSpreads);
  }

  Future<Map<String, dynamic>> credits() async {
    return _api.get<Map<String, dynamic>>(Api.fortuneCredits);
  }

  Future<Map<String, dynamic>> history({int perPage = 20}) async {
    return _api.get<Map<String, dynamic>>(
      Api.fortuneHistory,
      query: {'per_page': perPage},
    );
  }

  /// Begin a session: deduct credits + receive picked cards.
  /// Returns: { reading_id, cards: [{tarot_id, position, reversed}], requires_payment, price }
  Future<Map<String, dynamic>> draw({
    required String spread,
    String? category,
    String? question,
  }) async {
    return _api.post<Map<String, dynamic>>(Api.fortuneDraw, data: {
      'spread': spread,
      if (category != null) 'category': category,
      if (question != null) 'question': question,
    });
  }

  /// Generate AI interpretation for a previously drawn reading.
  Future<Map<String, dynamic>> read(int readingId) async {
    return _api.post<Map<String, dynamic>>(Api.fortuneRead, data: {
      'reading_id': readingId,
    });
  }
}

final fortuneRepositoryProvider = FutureProvider<FortuneRepository>((ref) async {
  final api = await ref.watch(apiClientProvider.future);
  return FortuneRepository(api);
});

/// Convenience providers used across the UI.
final fortuneCreditsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final repo = await ref.watch(fortuneRepositoryProvider.future);
  final res = await repo.credits();
  return (res['data'] is Map<String, dynamic>) ? res['data'] as Map<String, dynamic> : res;
});

final fortuneHistoryProvider = FutureProvider<List<dynamic>>((ref) async {
  final repo = await ref.watch(fortuneRepositoryProvider.future);
  final res = await repo.history();
  return (res['data'] is List) ? res['data'] as List : const [];
});
