import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'endpoints.dart';

/// Wallet — balance, transactions, PromptPay top-up start.
///
/// juntraweb is the source of truth. Slip image upload still happens via
/// the existing web `/wallet/topup/{tx}` page (the API returns the URL
/// in `slip_upload_url`); the Flutter app opens that URL in an in-app
/// webview to keep one upload flow shared with the web UI.
class WalletRepository {
  WalletRepository(this._api);
  final ApiClient _api;

  /// Balance + currency + recent transactions + per-feature pricing.
  Future<Map<String, dynamic>> overview() async {
    final res = await _api.get<Map<String, dynamic>>(Api.wallet);
    return _data(res);
  }

  /// Cursor-paged transactions list. Returns {data:List, meta:{next_cursor}}.
  Future<Map<String, dynamic>> transactions({int limit = 25, String? cursor}) async {
    final res = await _api.get<Map<String, dynamic>>(
      Api.walletTransactions,
      query: {
        'limit': limit,
        if (cursor != null) 'cursor': cursor,
      },
    );
    return res;
  }

  /// Initiates a PromptPay top-up. Returns:
  ///   {transaction:{id,...}, promptpay:{id,name},
  ///    slip_upload_url, instructions}
  Future<Map<String, dynamic>> startPromptPayTopup({required double amount}) async {
    final res = await _api.post<Map<String, dynamic>>(
      Api.walletTopupPromptpay,
      data: {'amount': amount},
    );
    return _data(res);
  }

  Map<String, dynamic> _data(Map<String, dynamic> res) {
    final inner = res['data'];
    return inner is Map<String, dynamic> ? inner : res;
  }
}

final walletRepositoryProvider = FutureProvider<WalletRepository>((ref) async {
  final api = await ref.watch(apiClientProvider.future);
  return WalletRepository(api);
});
