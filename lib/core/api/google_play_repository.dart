import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'endpoints.dart';

/// แพ็กเครดิตหนึ่งแพ็กตามที่เซิร์ฟเวอร์ขาย (ราคาขายจริงมาจาก Google Play)
@immutable
class ServerCreditPack {
  const ServerCreditPack({required this.productId, required this.credits});
  final String productId;
  final num credits;
}

/// `GET /v1/wallet/google-play`
@immutable
class GooglePlayCatalog {
  const GooglePlayCatalog({
    required this.enabled,
    required this.products,
    required this.accountId,
    this.balance,
  });

  /// ปิด = ไม่มีหน้าซื้อในแอพเลย (ใช้เครดิตที่มีได้อย่างเดียว) — ห้ามชี้ไปจ่ายที่อื่นแทน
  final bool enabled;
  final List<ServerCreditPack> products;

  /// obfuscatedAccountId ที่ส่งให้ Google ตอนซื้อ — เซิร์ฟเวอร์ใช้ผูก token กับบัญชี
  final String accountId;
  final double? balance;
}

/// ผลของ `POST /v1/wallet/google-play/redeem`
@immutable
class RedeemResult {
  const RedeemResult({required this.state, this.credits, this.balance, this.message});

  /// credited (เพิ่งเติม) · already (เคยเติมแล้ว) · pending (ยังไม่ได้เงิน)
  final String state;
  final num? credits;
  final double? balance;
  final String? message;
}

/// สิ่งที่ตัวจัดการการซื้อ (PlayBilling) ต้องการจากเซิร์ฟเวอร์ — แยกเป็น interface ให้เทสต์ได้
abstract interface class GooglePlayApi {
  Future<GooglePlayCatalog> catalog();
  Future<RedeemResult> redeem({required String productId, required String purchaseToken});
}

class GooglePlayRepository implements GooglePlayApi {
  GooglePlayRepository(this._api);
  final ApiClient _api;

  @override
  Future<GooglePlayCatalog> catalog() async {
    final res = await _api.get<Map<String, dynamic>>(Api.walletGooglePlay);
    final d = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : res;
    final list = d['products'] is List ? d['products'] as List : const [];
    return GooglePlayCatalog(
      enabled: d['enabled'] == true,
      accountId: d['account_id']?.toString() ?? '',
      balance: (d['balance'] as num?)?.toDouble(),
      products: [
        for (final p in list.whereType<Map>())
          if ((p['product_id']?.toString() ?? '').isNotEmpty && p['credits'] is num)
            ServerCreditPack(productId: p['product_id'].toString(), credits: p['credits'] as num),
      ],
    );
  }

  /// ส่ง purchase token ให้เซิร์ฟเวอร์ตรวจกับ Google — ปลอดภัยต่อการส่งซ้ำ (เติมครั้งเดียวต่อ token)
  /// Throws [ApiException]: 409 account_mismatch/token_used · 422 purchase_invalid/
  /// purchase_canceled/unknown_product · 503 billing_retry/billing_unavailable
  @override
  Future<RedeemResult> redeem({required String productId, required String purchaseToken}) async {
    final res = await _api.post<Map<String, dynamic>>(Api.walletGooglePlayRedeem, data: {
      'product_id': productId,
      'purchase_token': purchaseToken,
    });
    final d = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : res;
    return RedeemResult(
      state: d['state']?.toString() ?? 'credited',
      credits: d['credits'] as num?,
      balance: (d['balance'] as num?)?.toDouble(),
      message: d['message']?.toString(),
    );
  }
}

final googlePlayRepositoryProvider = FutureProvider<GooglePlayRepository>((ref) async {
  final api = await ref.watch(apiClientProvider.future);
  return GooglePlayRepository(api);
});
