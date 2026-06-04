import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'endpoints.dart';

/// Wallet — balance, transactions, PromptPay top-up start + native
/// slip upload.
///
/// juntraweb is the source of truth. Either the user uploads the slip
/// natively here (via [uploadTopupSlip]) and the wallet screen shows a
/// "waiting for admin approval" pill, or — fallback — they tap the
/// `slip_upload_url` returned alongside the initiate call to do it on
/// the web. Both paths feed the same WalletTransaction.slip_path so
/// the admin Filament approval flow doesn't care which client posted.
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
        'cursor': ?cursor,
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

  /// Fetch the latest state of a top-up transaction — includes
  /// `slip_uploaded` so the UI knows whether to show "อัปโหลดสลิป"
  /// or "รออนุมัติ".
  Future<Map<String, dynamic>> topupShow(int id) async {
    final res = await _api.get<Map<String, dynamic>>(Api.walletTopup(id));
    return _data(res);
  }

  /// Native slip upload. [filePath] is the local path returned by
  /// image_picker. Returns the updated transaction payload.
  ///
  /// Throws [ApiException] on:
  ///   - 409 — tx already approved/rejected
  ///   - 422 — invalid image / not a topup tx
  ///   - 401 — session expired
  Future<Map<String, dynamic>> uploadTopupSlip({
    required int transactionId,
    required String filePath,
    String? fileName,
  }) async {
    final form = FormData.fromMap({
      'slip': await MultipartFile.fromFile(
        filePath,
        filename: fileName ?? 'slip.jpg',
      ),
    });
    final res = await _api.postMultipart<Map<String, dynamic>>(
      Api.walletTopupSlip(transactionId),
      formData: form,
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
