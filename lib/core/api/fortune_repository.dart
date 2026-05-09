import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'endpoints.dart';

/// Reading history — wraps `/v1/history/readings*`.
///
/// AI generation itself happens through the existing web flow (the
/// shuffle-and-reveal screens currently render results client-side from
/// the local TAROT_DECK; persisting them to the user's history is a
/// future endpoint). This repository is the read-side surface for the
/// History tab on the home screen and the dedicated `/history` route.
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
        if (cursor != null) 'cursor': cursor,
        if (type != null) 'type': type,
      },
    );
  }

  /// Get a single reading with cards (for tarot) and full AI interpretation.
  Future<Map<String, dynamic>> reading(int id) async {
    final res = await _api.get<Map<String, dynamic>>(Api.historyReading(id));
    final inner = res['data'];
    return inner is Map<String, dynamic> ? inner : res;
  }
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
