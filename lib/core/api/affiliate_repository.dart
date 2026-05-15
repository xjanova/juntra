import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'endpoints.dart';

/// MLM affiliate dashboard — wraps `/v1/mlm/*` which proxies to the
/// upstream Thaiprompt-Affiliate API via the user's thaiprompt_token.
///
/// Linkage state model: every method returns a [MlmResult] which is
/// either [MlmLinked] (real data) or [MlmNotLinked] (403 from the
/// backend with `reason_code: thaiprompt_not_linked`). The screen
/// branches on this without us throwing — "not linked" is an expected
/// app state, not an error.
///
/// Other 4xx/5xx still throw [ApiException] so the screen falls into
/// its generic error state.
class AffiliateRepository {
  AffiliateRepository(this._api);
  final ApiClient _api;

  Future<MlmResult> stats() async {
    return _wrap(() => _api.get<Map<String, dynamic>>(Api.mlmStats));
  }

  Future<MlmResult> tree({int depth = 5}) async {
    return _wrap(() => _api.get<Map<String, dynamic>>(
          Api.mlmTree,
          query: {'depth': depth},
        ));
  }

  Future<MlmResult> commissions({int page = 1, int perPage = 25}) async {
    return _wrap(() => _api.get<Map<String, dynamic>>(
          Api.mlmCommissions,
          query: {'page': page, 'per_page': perPage},
        ));
  }

  /// Unwrap the `{linked, data, meta?, reason_code?}` envelope. Note:
  /// the `data` field is heterogeneous — stats/tree are Maps while
  /// commissions is a List — so we keep it as `dynamic` and let the
  /// caller cast on use. The ApiClient sets `validateStatus < 500` so
  /// the 403 body still arrives as a normal Future.
  Future<MlmResult> _wrap(Future<Map<String, dynamic>> Function() fetch) async {
    final res = await fetch();
    if (res['linked'] == true) {
      return MlmLinked(
        payload: res['data'],
        meta: (res['meta'] as Map?)?.cast<String, dynamic>(),
      );
    }
    return MlmNotLinked(
      reasonCode: res['reason_code']?.toString() ?? 'unknown',
      message: res['message']?.toString()
          ?? 'ยังไม่ได้เชื่อมต่อบัญชี Thaiprompt',
    );
  }
}

/// Two-state result so the affiliate screen can branch without a
/// thrown-exception flow for the expected "not linked" case.
sealed class MlmResult {
  const MlmResult();
}

class MlmLinked extends MlmResult {
  const MlmLinked({required this.payload, this.meta});

  /// Raw `data` field from the envelope. Stats/tree are JSON objects;
  /// commissions is a JSON array. Callers cast appropriately:
  ///   `(linked.payload as Map?)?.cast<String, dynamic>()`
  ///   `(linked.payload as List?)?.cast<Map<String, dynamic>>()`
  final dynamic payload;

  /// Pagination meta — only present on commissions.
  final Map<String, dynamic>? meta;

  Map<String, dynamic> get asMap =>
      (payload is Map) ? Map<String, dynamic>.from(payload as Map) : const {};

  List<Map<String, dynamic>> get asList {
    if (payload is List) {
      return (payload as List).whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    return const [];
  }
}

class MlmNotLinked extends MlmResult {
  const MlmNotLinked({required this.reasonCode, required this.message});
  final String reasonCode;
  final String message;
}

final affiliateRepositoryProvider = FutureProvider<AffiliateRepository>((ref) async {
  final api = await ref.watch(apiClientProvider.future);
  return AffiliateRepository(api);
});

/// Bundle the three calls so the AffiliateScreen renders off one async
/// state. Stats fires first — if the user isn't linked, short-circuit
/// without two more pointless 403s. Tree + commissions run in parallel
/// once we know we're linked.
final affiliateBundleProvider = FutureProvider<MlmResult>((ref) async {
  final repo = await ref.watch(affiliateRepositoryProvider.future);

  final statsResult = await repo.stats();
  if (statsResult is MlmNotLinked) return statsResult;

  final results = await Future.wait<MlmResult>([
    repo.tree(depth: 5),
    repo.commissions(page: 1, perPage: 25),
  ]);
  final treeResult = results[0];
  final commissionsResult = results[1];

  if (treeResult is MlmNotLinked) return treeResult;
  if (commissionsResult is MlmNotLinked) return commissionsResult;

  // Type-promoted after the `is MlmNotLinked` guards above — but the
  // sealed class type promotion is narrowed only to "not MlmNotLinked",
  // not "is MlmLinked", so the casts stay. Dart 3.4 doesn't promote
  // through the sealed-class exhaustiveness check yet.
  final statsLinked       = statsResult       as MlmLinked;
  final treeLinked        = treeResult        as MlmLinked;
  final commissionsLinked = commissionsResult as MlmLinked;
  return MlmLinked(
    payload: <String, dynamic>{
      'stats':       statsLinked.asMap,
      'tree':        treeLinked.asMap,
      'commissions': commissionsLinked.asList,
    },
    meta: commissionsLinked.meta,
  );
});
