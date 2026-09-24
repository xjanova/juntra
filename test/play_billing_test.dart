import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:juntra/core/api/api_exceptions.dart';
import 'package:juntra/core/api/google_play_repository.dart';
import 'package:juntra/core/billing/play_billing.dart';

/// ตรรกะเงินของการซื้อเครดิตผ่าน Google Play (ฝั่งแอพ)
///
/// สิ่งที่ห้ามพัง: consume ในเครื่องได้ **หลัง** เซิร์ฟเวอร์เติมเครดิตแล้วเท่านั้น
/// (consume ก่อน = ถ้าเน็ตหลุดตรงกลาง ลูกค้าจ่ายแล้วไม่ได้เครดิต และการซื้อหายจาก Play)
class _FakeGateway implements PlayStoreGateway {
  final controller = StreamController<List<PurchaseDetails>>.broadcast();
  final consumed = <String>[];
  bool available = true;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => controller.stream;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<List<ProductDetails>> queryProducts(Set<String> ids) async => [
        for (final id in ids)
          ProductDetails(id: id, title: id, description: '', price: '฿59.00', rawPrice: 59, currencyCode: 'THB'),
      ];
  @override
  Future<bool> buyConsumable(ProductDetails product, {required String accountId}) async => true;
  @override
  Future<void> restore() async {}
  @override
  Future<void> consume(PurchaseDetails purchase) async =>
      consumed.add(purchase.verificationData.serverVerificationData);
}

class _FakeServer implements GooglePlayApi {
  final redeemed = <String>[];
  RedeemResult Function(String token) respond = (_) => const RedeemResult(state: 'credited', credits: 50, balance: 60);
  Object? error;
  Completer<void>? gate;

  @override
  Future<GooglePlayCatalog> catalog() async => const GooglePlayCatalog(
        enabled: true,
        accountId: 'acct-hash',
        products: [ServerCreditPack(productId: 'juntra_credits_50', credits: 50)],
      );

  @override
  Future<RedeemResult> redeem({required String productId, required String purchaseToken}) async {
    redeemed.add(purchaseToken);
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return respond(purchaseToken);
  }
}

PurchaseDetails _purchase(String token, {PurchaseStatus status = PurchaseStatus.purchased, String product = 'juntra_credits_50'}) {
  return PurchaseDetails(
    purchaseID: 'GPA.$token',
    productID: product,
    verificationData: PurchaseVerificationData(
      localVerificationData: '{}',
      serverVerificationData: token,
      source: 'google_play',
    ),
    transactionDate: '0',
    status: status,
  );
}

void main() {
  late _FakeGateway gateway;
  late _FakeServer server;
  late PlayBilling billing;
  late List<BillingEvent> events;
  var balanceRefreshes = 0;

  setUp(() async {
    gateway = _FakeGateway();
    server = _FakeServer();
    balanceRefreshes = 0;
    billing = PlayBilling(
      gateway: gateway,
      repository: () async => server,
      onBalanceChanged: () => balanceRefreshes++,
    );
    events = [];
    billing.events.listen(events.add);
    // แพ็กที่เซิร์ฟเวอร์ขาย — ใช้กรองการซื้อที่ไม่ใช่ของเรา
    expect(await billing.loadPacks(), isA<PacksReady>());
  });

  test('ซื้อสำเร็จ: ส่ง token ให้เซิร์ฟเวอร์ แล้ว consume หลังเติมเครดิต', () async {
    await billing.handlePurchases([_purchase('tok-1')]);
    await Future<void>.delayed(Duration.zero);

    expect(server.redeemed, ['tok-1']);
    expect(gateway.consumed, ['tok-1']);
    expect(balanceRefreshes, 1);
    expect(events.single, isA<BillingCredited>());
  });

  test('เซิร์ฟเวอร์ยังไม่ได้เงิน (pending) = ห้าม consume', () async {
    server.respond = (_) => const RedeemResult(state: 'pending', message: 'รอชำระ');
    await billing.handlePurchases([_purchase('tok-2')]);
    await Future<void>.delayed(Duration.zero);

    expect(gateway.consumed, isEmpty);
    expect(events.single, isA<BillingPending>());
  });

  test('เซิร์ฟเวอร์ปฏิเสธ (บัญชีไม่ตรง) = ห้าม consume และบอกผู้ใช้', () async {
    server.error = ApiException(statusCode: 409, message: 'การซื้อนี้เป็นของบัญชีอื่น', reasonCode: 'account_mismatch');
    await billing.handlePurchases([_purchase('tok-3')]);
    await Future<void>.delayed(Duration.zero);

    expect(gateway.consumed, isEmpty);
    expect((events.single as BillingFailed).message, contains('บัญชีอื่น'));
  });

  test('ยังไม่ได้ล็อกอิน (401) = เก็บการซื้อไว้เงียบ ๆ รอส่งใหม่', () async {
    server.error = ApiException(statusCode: 401, message: 'unauth');
    await billing.handlePurchases([_purchase('tok-4')]);
    await Future<void>.delayed(Duration.zero);

    expect(gateway.consumed, isEmpty);
    expect(events, isEmpty);
  });

  test('เน็ตหลุดตอนยืนยัน = ไม่ consume (ส่งใหม่ครั้งหน้าได้)', () async {
    server.error = StateError('socket closed');
    await billing.handlePurchases([_purchase('tok-5')]);
    await Future<void>.delayed(Duration.zero);

    expect(gateway.consumed, isEmpty);
    expect(events.single, isA<BillingFailed>());
  });

  test('การซื้อที่เก็บตกได้ (restored) และเคยเติมแล้ว: consume ได้ แต่ไม่แจ้งเติมซ้ำ', () async {
    server.respond = (_) => const RedeemResult(state: 'already', credits: 50, balance: 60);
    await billing.handlePurchases([_purchase('tok-6', status: PurchaseStatus.restored)]);
    await Future<void>.delayed(Duration.zero);

    expect(gateway.consumed, ['tok-6']);
    expect(events, isEmpty);
  });

  test('token เดียวกันมาซ้ำระหว่างที่ยังยืนยันอยู่ = ส่งเซิร์ฟเวอร์ครั้งเดียว', () async {
    server.gate = Completer<void>();
    final first = billing.handlePurchases([_purchase('tok-7')]);
    final second = billing.handlePurchases([_purchase('tok-7', status: PurchaseStatus.restored)]);
    server.gate!.complete();
    await Future.wait([first, second]);

    expect(server.redeemed, ['tok-7']);
    expect(gateway.consumed, ['tok-7']);
  });

  test('ของที่ไม่ใช่แพ็กเครดิตของเรา — ไม่แตะเลย', () async {
    await billing.handlePurchases([_purchase('tok-8', product: 'some_other_product')]);
    await Future<void>.delayed(Duration.zero);

    expect(server.redeemed, isEmpty);
    expect(gateway.consumed, isEmpty);
  });

  test('ผู้ใช้ยกเลิกหน้าจ่ายเงิน — ไม่มีอะไรถูกส่ง', () async {
    await billing.handlePurchases([_purchase('tok-9', status: PurchaseStatus.canceled)]);
    await Future<void>.delayed(Duration.zero);

    expect(server.redeemed, isEmpty);
    expect(events.single, isA<BillingCanceled>());
  });

  test('หลังบ้านปิดการขายผ่าน Play — ไม่มีหน้าซื้อ', () async {
    final closed = PlayBilling(
      gateway: gateway,
      repository: () async => _ClosedServer(),
      onBalanceChanged: () {},
    );
    expect(await closed.loadPacks(), isA<PacksDisabled>());
  });

  test('เครื่องไม่มี Play Store — บอกว่าซื้อไม่ได้ ไม่เปิดหน้าจ่าย', () async {
    gateway.available = false;
    expect(await billing.loadPacks(), isA<PacksUnavailable>());
  });
}

class _ClosedServer implements GooglePlayApi {
  @override
  Future<GooglePlayCatalog> catalog() async =>
      const GooglePlayCatalog(enabled: false, accountId: 'x', products: []);
  @override
  Future<RedeemResult> redeem({required String productId, required String purchaseToken}) =>
      throw UnimplementedError();
}
