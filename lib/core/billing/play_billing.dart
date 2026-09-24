import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../api/api_exceptions.dart';
import '../api/google_play_repository.dart';
import '../app_channel.dart';
import '../auth/auth_state.dart';

/// ช่องทางคุยกับ Google Play Billing — แยกเป็น interface ให้เทสต์ตรรกะเงินได้โดยไม่ต้องมี Play
abstract class PlayStoreGateway {
  Stream<List<PurchaseDetails>> get purchaseStream;
  Future<bool> isAvailable();
  Future<List<ProductDetails>> queryProducts(Set<String> ids);
  Future<bool> buyConsumable(ProductDetails product, {required String accountId});

  /// ให้ Play ส่งการซื้อที่ยังไม่ consume กลับมาทาง [purchaseStream] (สถานะ restored)
  Future<void> restore();

  /// consume ในเครื่อง — ให้คลังของ Play ในเครื่องรู้ทันทีว่าซื้อแพ็กเดิมซ้ำได้
  /// (เซิร์ฟเวอร์ consume ไปแล้วก็ไม่เป็นไร Play ตอบ error ซึ่งเราไม่สนใจ)
  Future<void> consume(PurchaseDetails purchase);
}

class InAppPurchaseGateway implements PlayStoreGateway {
  InAppPurchase get _iap => InAppPurchase.instance;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;

  @override
  Future<bool> isAvailable() => _iap.isAvailable();

  @override
  Future<List<ProductDetails>> queryProducts(Set<String> ids) async {
    final res = await _iap.queryProductDetails(ids);
    return res.productDetails;
  }

  @override
  Future<bool> buyConsumable(ProductDetails product, {required String accountId}) {
    return _iap.buyConsumable(
      purchaseParam: PurchaseParam(productDetails: product, applicationUserName: accountId),
      // 🔴 ห้าม autoConsume — ปลั๊กอินจะ consume ทันทีในเครื่องก่อนเซิร์ฟเวอร์ได้ตรวจและเติมเครดิต
      // เซิร์ฟเวอร์เป็นคน consume หลังเติมเครดิตแล้วเท่านั้น
      autoConsume: false,
    );
  }

  @override
  Future<void> restore() => _iap.restorePurchases();

  @override
  Future<void> consume(PurchaseDetails purchase) async {
    try {
      final android = _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      await android.consumePurchase(purchase);
    } catch (_) {/* เซิร์ฟเวอร์ consume ไปแล้ว — ไม่ใช่ข้อผิดพลาด */}
  }
}

/// แพ็กเครดิตที่ขายได้จริงบนเครื่องนี้ (เซิร์ฟเวอร์บอกเครดิต · Play บอกราคา)
@immutable
class CreditPack {
  const CreditPack({required this.productId, required this.credits, required this.product});
  final String productId;
  final num credits;
  final ProductDetails product;
  String get price => product.price;
}

/// สิ่งที่เกิดกับการซื้อ — หน้าจอฟังแล้วแสดงผล
sealed class BillingEvent {
  const BillingEvent();
}

class BillingCredited extends BillingEvent {
  const BillingCredited({required this.credits, this.balance, required this.message});
  final num credits;
  final double? balance;
  final String message;
}

class BillingPending extends BillingEvent {
  const BillingPending(this.message);
  final String message;
}

class BillingFailed extends BillingEvent {
  const BillingFailed(this.message);
  final String message;
}

class BillingCanceled extends BillingEvent {
  const BillingCanceled();
}

/// ผลการเตรียมหน้าซื้อ
sealed class PacksResult {
  const PacksResult();
}

class PacksReady extends PacksResult {
  const PacksReady(this.packs);
  final List<CreditPack> packs;
}

/// เซิร์ฟเวอร์ปิดการขายผ่าน Play — แอพไม่มีหน้าซื้อ (ห้ามชี้ไปจ่ายช่องทางอื่นแทน)
class PacksDisabled extends PacksResult {
  const PacksDisabled();
}

/// เครื่องนี้ซื้อผ่าน Play ไม่ได้ (ไม่มี Play Store / ไม่ได้ติดตั้งจาก Play / เน็ตหลุด)
class PacksUnavailable extends PacksResult {
  const PacksUnavailable(this.message);
  final String message;
}

/// ตัวจัดการการซื้อเครดิตผ่าน Google Play ของแอพช่อง Play
///
/// กติกาเรื่องเงิน (ฝั่งแอพ):
///   1. ไม่เติมเครดิตเอง — ส่ง purchase token ให้เซิร์ฟเวอร์ ซึ่งถาม Google เองแล้วเติมครั้งเดียวต่อ token
///   2. consume หลังเซิร์ฟเวอร์ยืนยันแล้วเท่านั้น — ไม่งั้นถ้าเน็ตหลุดกลางทาง เงินลูกค้าหาย
///      ส่วนการซื้อที่ยังไม่ consume จะถูก [restorePending] เก็บตกตอนเปิดแอพ/ล็อกอินครั้งหน้า
///   3. จ่ายแบบรอชำระ (pending) = ยังไม่เติม เซิร์ฟเวอร์ตอบ pending จนกว่า Google จะได้เงิน
class PlayBilling {
  PlayBilling({
    required PlayStoreGateway gateway,
    required Future<GooglePlayApi> Function() repository,
    required void Function() onBalanceChanged,
  })  : _gateway = gateway,
        _repository = repository,
        _onBalanceChanged = onBalanceChanged;

  final PlayStoreGateway _gateway;
  final Future<GooglePlayApi> Function() _repository;
  final void Function() _onBalanceChanged;

  final _events = StreamController<BillingEvent>.broadcast();
  StreamSubscription<List<PurchaseDetails>>? _sub;
  final Set<String> _inFlight = {};

  /// product id → เครดิต ของแพ็กที่เซิร์ฟเวอร์ขาย (โหลดล่าสุด) — ใช้กรองการซื้อที่ไม่ใช่ของเรา
  Map<String, num> _known = const {};

  Stream<BillingEvent> get events => _events.stream;

  /// เริ่มฟังการซื้อ — ครั้งเดียวต่อรอบเปิดแอพ (การซื้อที่เสร็จตอนแอพปิดอยู่จะมาทางนี้ด้วย)
  void start() {
    _sub ??= _gateway.purchaseStream.listen(
      (list) => unawaited(handlePurchases(list)),
      onError: (Object e) => _events.add(const BillingFailed('ร้านค้า Google Play ขัดข้อง กรุณาลองใหม่')),
    );
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _events.close();
  }

  /// เตรียมหน้าซื้อ: แพ็กจากเซิร์ฟเวอร์ + ราคาจาก Play
  Future<PacksResult> loadPacks() async {
    final GooglePlayCatalog catalog;
    try {
      catalog = await (await _repository()).catalog();
    } on ApiException catch (e) {
      return PacksUnavailable(e.message);
    } catch (_) {
      return const PacksUnavailable('เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ กรุณาลองใหม่');
    }
    if (!catalog.enabled || catalog.products.isEmpty) return const PacksDisabled();
    _known = {for (final p in catalog.products) p.productId: p.credits};
    _accountId = catalog.accountId;

    if (!await _gateway.isAvailable()) {
      return const PacksUnavailable('เครื่องนี้ยังซื้อผ่าน Google Play ไม่ได้ — ตรวจว่าเข้าสู่ระบบ Play Store แล้ว');
    }
    final details = await _gateway.queryProducts(_known.keys.toSet());
    final byId = {for (final d in details) d.id: d};
    final packs = [
      for (final p in catalog.products)
        if (byId[p.productId] != null)
          CreditPack(productId: p.productId, credits: p.credits, product: byId[p.productId]!),
    ];
    if (packs.isEmpty) {
      return const PacksUnavailable('ยังไม่มีแพ็กเครดิตในร้านค้า Google Play — กรุณาลองใหม่ภายหลัง');
    }
    return PacksReady(packs);
  }

  String _accountId = '';

  /// เปิดหน้าจ่ายเงินของ Google Play — ผลมาทาง [events]
  Future<bool> buy(CreditPack pack) async {
    if (_accountId.isEmpty) return false;
    try {
      return await _gateway.buyConsumable(pack.product, accountId: _accountId);
    } catch (e) {
      // เช่น itemAlreadyOwned — การซื้อครั้งก่อนยังไม่ถูกส่งมอบ: เก็บตกแล้วลูกค้าซื้อใหม่ได้
      if (kDebugMode) debugPrint('[PlayBilling] buy failed: $e');
      unawaited(restorePending());
      _events.add(const BillingFailed('เปิดหน้าชำระเงินไม่สำเร็จ — กำลังตรวจการซื้อก่อนหน้า ลองใหม่อีกครั้งนะคะ'));
      return false;
    }
  }

  /// เก็บตกการซื้อที่จ่ายแล้วแต่ยังไม่ได้เครดิต (แอพปิด/เน็ตหลุดกลางทาง)
  Future<void> restorePending() async {
    try {
      if (_known.isEmpty) {
        final catalog = await (await _repository()).catalog();
        _known = {for (final p in catalog.products) p.productId: p.credits};
        if (_accountId.isEmpty) _accountId = catalog.accountId;
      }
      if (!await _gateway.isAvailable()) return;
      await _gateway.restore();
    } catch (e) {
      if (kDebugMode) debugPrint('[PlayBilling] restore failed: $e');
    }
  }

  @visibleForTesting
  Future<void> handlePurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          _events.add(const BillingPending('รอการชำระเงินกับ Google Play — เครดิตจะเข้าอัตโนมัติเมื่อชำระเรียบร้อย'));
        case PurchaseStatus.canceled:
          _events.add(const BillingCanceled());
        case PurchaseStatus.error:
          _events.add(BillingFailed(_friendlyError(p.error)));
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _deliver(p);
      }
    }
  }

  Future<void> _deliver(PurchaseDetails p) async {
    // ของที่ไม่ใช่แพ็กเครดิตของเรา (หรือรู้ไม่ได้ว่าใช่) — ไม่แตะ ไม่ consume
    if (_known.isNotEmpty && !_known.containsKey(p.productID)) return;
    final token = p.verificationData.serverVerificationData;
    if (token.isEmpty || !_inFlight.add(token)) return; // กำลังส่งอยู่แล้ว (stream ส่งซ้ำ)

    try {
      final result = await (await _repository()).redeem(productId: p.productID, purchaseToken: token);
      if (result.state == 'pending') {
        _events.add(BillingPending(result.message ?? 'รอการชำระเงินกับ Google Play'));
        return;
      }
      // เซิร์ฟเวอร์เติมเครดิต (และ consume) แล้ว — consume ในเครื่องด้วยให้ซื้อแพ็กเดิมซ้ำได้ทันที
      await _gateway.consume(p);
      _onBalanceChanged();
      if (result.state == 'credited') {
        _events.add(BillingCredited(
          credits: result.credits ?? _known[p.productID] ?? 0,
          balance: result.balance,
          message: result.message ?? 'เติมเครดิตเรียบร้อยแล้วค่ะ',
        ));
      }
    } on ApiException catch (e) {
      // ไม่ consume ในทุกกรณีที่เซิร์ฟเวอร์ยังไม่ได้เติมเครดิต — การซื้อยังค้างอยู่ใน Play
      // และจะถูกส่งมาใหม่ตอนเปิดแอพ/ล็อกอินครั้งหน้า (401 = ยังไม่ล็อกอิน รอไว้ก่อน)
      if (e.statusCode == 401) return;
      _events.add(BillingFailed(e.message));
    } catch (_) {
      _events.add(const BillingFailed('ยืนยันการซื้อไม่สำเร็จ — การซื้อของลูกค้าปลอดภัย แอพจะลองยืนยันอีกครั้งอัตโนมัติ'));
    } finally {
      _inFlight.remove(token);
    }
  }

  static String _friendlyError(IAPError? e) {
    final code = e?.code ?? '';
    if (code.contains('ItemAlreadyOwned') || code.contains('itemAlreadyOwned')) {
      return 'การซื้อครั้งก่อนยังส่งมอบไม่เสร็จ — กำลังตรวจสอบให้อัตโนมัติ';
    }
    return 'การชำระเงินไม่สำเร็จ — ยังไม่มีการเรียกเก็บเงิน';
  }
}

/// ตัวจัดการการซื้อ (มีเฉพาะแอพช่อง Play — ช่อง APK ได้ null)
final playBillingProvider = Provider<PlayBilling?>((ref) {
  if (!isPlayChannel) return null;
  final billing = PlayBilling(
    gateway: InAppPurchaseGateway(),
    repository: () => ref.read(googlePlayRepositoryProvider.future),
    onBalanceChanged: () => ref.read(authControllerProvider.notifier).refresh(),
  );
  ref.onDispose(billing.dispose);
  return billing;
});
