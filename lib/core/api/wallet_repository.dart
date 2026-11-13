import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'endpoints.dart';
import '../auth/session.dart';

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

  /// All of the user's top-ups (newest first), optionally filtered by status.
  /// Each carries `slip_uploaded` + `expires_at`; `meta.pending_count`. Lets
  /// the app surface pending top-ups older than the last-10 overview window.
  Future<Map<String, dynamic>> topups({String? status}) async {
    final res = await _api.get<Map<String, dynamic>>(
      Api.walletTopups,
      query: {'status': ?status},
    );
    return res;
  }

  /// Initiates a PromptPay top-up. Returns:
  ///   {transaction:{id,...}, promptpay:{id,name},
  ///    slip_upload_url, instructions}
  /// [idempotencyKey] — RetryInterceptor ยิง POST ซ้ำเองเมื่อ timeout/5xx
  /// ถ้าไม่ส่งคีย์ สัญญาณตกครั้งเดียวได้รายการ pending ซ้ำหลายใบ ยอดสตางค์
  /// คนละค่า ลูกค้าไม่รู้ว่าต้องโอนใบไหน และไปกินเพดาน pending จนสร้างใหม่ไม่ได้
  ///
  /// [method] = `promptpay` (ค่าเริ่มต้น) หรือ `kbank` (โอนเข้าบัญชี) เหมือนเว็บ —
  /// เซิร์ฟเวอร์เก่าไม่รู้จักคีย์นี้และถือเป็น PromptPay จึงส่งเฉพาะตอนเป็น kbank
  Future<Map<String, dynamic>> startPromptPayTopup({
    required double amount,
    String? idempotencyKey,
    String method = 'promptpay',
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      Api.walletTopupPromptpay,
      idempotencyKey: idempotencyKey,
      data: {
        'amount': amount,
        if (method != 'promptpay') 'method': method,
      },
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

  /// Cancel a still-pending top-up (releases the reserved amount). Throws
  /// [ApiException] with 409 if it's no longer pending (already approved/
  /// rejected) so the UI can refresh instead of insisting.
  Future<void> cancelTopup(int id) async {
    await _api.delete<dynamic>(Api.walletTopupCancel(id));
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

/// บัญชีธนาคารสำหรับโอนตรง (`topup.kbank`)
class KbankAccount {
  const KbankAccount({required this.bank, required this.name, required this.number, this.displayNumber});
  final String bank;
  final String name;
  final String number;
  final String? displayNumber;

  static KbankAccount? fromJson(Object? j) {
    if (j is! Map) return null;
    final number = (j['number'] ?? '').toString().trim();
    if (number.isEmpty) return null;
    return KbankAccount(
      bank: (j['bank'] ?? 'กสิกรไทย').toString(),
      name: (j['name'] ?? '').toString(),
      number: number,
      displayNumber: j['display_number']?.toString(),
    );
  }
}

/// กติกาเติมเงินจาก `GET /v1/wallet` → `topup` (ชุดเดียวกับหน้าเติมเงินของเว็บ)
///
/// เซิร์ฟเวอร์ละ `topup` ทิ้งเมื่อแอพส่ง `X-App-Channel: play` (นโยบาย Play) และ
/// เซิร์ฟเวอร์เก่าไม่มีคีย์นี้ — ทั้งสองกรณีได้ [fallback] ที่ตรงกับแอพ 0.6.0
class WalletTopupConfig {
  const WalletTopupConfig({
    required this.bundles,
    required this.min,
    required this.max,
    required this.channels,
    this.kbank,
    this.fromServer = false,
  });

  final List<int> bundles;
  final num min;
  final num max;

  /// `promptpay` · `kbank` — ช่องทางที่เปิดอยู่
  final List<String> channels;
  final KbankAccount? kbank;
  final bool fromServer;

  bool get hasKbank => channels.contains('kbank') && kbank != null;

  static const fallback = WalletTopupConfig(
    bundles: [50, 100, 200, 500, 1000, 2000],
    min: 20,
    max: 50000,
    channels: ['promptpay'],
  );

  static WalletTopupConfig fromJson(Object? j) {
    if (j is! Map) return fallback;
    final bundles = <int>[
      if (j['bundles'] is List)
        for (final b in j['bundles'] as List)
          if (num.tryParse('$b') case final n? when n > 0) n.toInt(),
    ];
    final channels = <String>[
      if (j['channels'] is List)
        for (final c in j['channels'] as List) c.toString(),
    ];
    return WalletTopupConfig(
      bundles: j['bundles'] is List ? bundles : fallback.bundles,
      min: num.tryParse('${j['min']}') ?? fallback.min,
      max: num.tryParse('${j['max']}') ?? fallback.max,
      channels: j['channels'] is List ? channels : fallback.channels,
      kbank: KbankAccount.fromJson(j['kbank']),
      fromServer: true,
    );
  }
}

final walletRepositoryProvider = FutureProvider<WalletRepository>((ref) async {
  final api = await ref.watch(apiClientProvider.future);
  return WalletRepository(api);
});

/// Per-feature pricing from `GET /v1/wallet` (`pricing` map), keyed by the
/// backend feature key (`tarot_three`, `tarot_celtic`, `chat_message`, …).
/// The app reads this so spread/feature prices always match what the backend
/// actually debits — never a hardcoded number that can drift.
final walletPricingProvider = FutureProvider<Map<String, num>>((ref) async {
  // ต้องล็อกอิน — แขกได้ 401 แล้วค้างเป็น error ทั้งรอบเปิดแอพ (ราคาไม่ขึ้นจนกว่าจะปิดแอพ)
  // watch ไว้ให้โหลดใหม่ทันทีที่ล็อกอิน
  ref.watch(sessionUserIdProvider);
  final repo = await ref.watch(walletRepositoryProvider.future);
  final data = await repo.overview();
  final p = data['pricing'];
  if (p is Map) {
    return {
      for (final e in p.entries)
        e.key.toString():
            (e.value is num) ? e.value as num : (num.tryParse('${e.value}') ?? 0),
    };
  }
  return const {};
});

/// ชุดยอดเติม/ช่องทางจาก `GET /v1/wallet` → `topup` — ช่อง play ไม่ใช้ provider นี้
/// (ไม่มี UI จ่ายนอก Play) แต่ถ้าถูกอ่านก็ได้ [WalletTopupConfig.fallback] เฉย ๆ
final walletTopupConfigProvider = FutureProvider<WalletTopupConfig>((ref) async {
  ref.watch(sessionUserIdProvider);
  final repo = await ref.watch(walletRepositoryProvider.future);
  final data = await repo.overview();
  return WalletTopupConfig.fromJson(data['topup']);
});
