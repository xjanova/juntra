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
  Future<Map<String, dynamic>> createTarotReading({
    required String type,
    String? question,
    required List<TarotPick> picks,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      Api.historyReadings,
      data: {
        'type': type,
        if (question != null && question.trim().isNotEmpty) 'question': question.trim(),
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
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      Api.fortuneNumerology,
      data: {'name': name, 'birth_date': birthDate},
    );
    return _readingId(res);
  }

  /// Create an auspicious-dates reading. The backend returns 422
  /// (`no_auspicious_day`) when the window has no good day → [ApiException].
  Future<int> createAuspicious({
    required String occasion,
    String? fromDate,
    String? toDate,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      Api.fortuneAuspicious,
      data: {
        'occasion': occasion,
        'from_date': ?fromDate,
        'to_date': ?toDate,
      },
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

/// Single reading detail — keyed by id so multiple opens don't collide.
final readingDetailProvider = FutureProvider.family<Map<String, dynamic>, int>((ref, id) async {
  final repo = await ref.watch(fortuneRepositoryProvider.future);
  return repo.reading(id);
});
