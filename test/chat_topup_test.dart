import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juntra/core/api/api_client.dart';
import 'package:juntra/core/api/api_exceptions.dart';
import 'package:juntra/core/api/chat_repository.dart';
import 'package:juntra/core/api/wallet_repository.dart';
import 'package:juntra/core/app_channel.dart';
import 'package:juntra/core/auth/auth_state.dart';
import 'package:juntra/features/chat/chat_topup_sheet.dart';

class _Wallet extends WalletRepository {
  _Wallet(super.api);
  final keys = <String?>[];
  final ids = <int>[];
  bool fail = false;
  Completer<Map<String, dynamic>>? creating;
  @override
  Future<Map<String, dynamic>> startPromptPayTopup({required double amount, String? idempotencyKey, String method = 'promptpay'}) async {
    keys.add(idempotencyKey);
    if (fail) throw ApiException(statusCode: 0, message: 'หมดเวลาเชื่อมต่อ');
    return creating?.future ?? {'id': 7, 'payable_amount': 100.37, 'promptpay': {'qr_payload': '000201'}};
  }
  @override
  Future<Map<String, dynamic>> topupShow(int id) async {
    ids.add(id);
    if (fail) throw ApiException(statusCode: 404, message: 'โหลดบิลเดิมไม่ได้ค่ะ');
    return {'id': id, 'status': 'pending', 'payable_amount': 100.37, 'promptpay': {'qr_payload': '000201'}};
  }
}

/// Flutter อนุญาตเฉพาะการเปลี่ยนสถานะทีละขั้น (resumed ↔ inactive ↔ hidden ↔ paused)
void _lifecycle(WidgetTester tester, {required bool foreground}) {
  final steps = foreground
      ? const [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]
      : const [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ];
  for (final s in steps) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
}

// เทสต์ช่อง APK (พร้อมเพย์) รันได้เฉพาะ `flutter test --flavor direct` —
// เทสต์ปกติไม่มี flavor = ถือเป็นช่อง Play จึงข้ามไป (ชีทต้องไม่โชว์อะไรเลยใน Play)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ApiClient api;
  late _Wallet wallet;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    api = await ApiClient.create();
    wallet = _Wallet(api);
  });
  tearDown(() => api.dio.close(force: true));

  Future<void> show(WidgetTester tester, {ChatPendingBill? resume}) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      apiClientProvider.overrideWith((_) => Completer<ApiClient>().future),
      authControllerProvider.overrideWith((ref) => AuthController(ref)),
      walletRepositoryProvider.overrideWith((_) async => wallet),
      walletTopupConfigProvider.overrideWith((_) async => const WalletTopupConfig(
        bundles: [100, 300], min: 20, max: 50000, channels: ['promptpay'], fromServer: true)),
    ], child: MaterialApp(home: Scaffold(body: ChatTopUpSheet(resume: resume)))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('direct bundles follow server and money retry keeps key', (tester) async {
    wallet.fail = true;
    await show(tester);
    expect(find.text('฿300'), findsOneWidget);
    expect(find.text('฿50'), findsNothing);
    await tester.tap(find.text('฿100'));
    await tester.pump();
    expect(wallet.keys, hasLength(1));
    wallet.fail = false;
    wallet.creating = Completer<Map<String, dynamic>>();
    await tester.tap(find.text('฿100'));
    await tester.pump();
    await tester.tap(find.text('฿100'));
    await tester.pump();
    expect(wallet.keys, hasLength(2));
    expect(wallet.keys.first, wallet.keys.last);
    wallet.creating!.complete({'id': 7, 'payable_amount': 100.37, 'promptpay': {'qr_payload': '000201'}});
    await tester.pump();
    expect(find.text('฿100.37'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
    expect(wallet.ids, isEmpty);
  }, skip: isPlayChannel);

  testWidgets('direct resume fetches existing transaction without creating one', (tester) async {
    await show(tester, resume: const ChatPendingBill(id: 7, ref: 'R7', amount: 100, payableAmount: 100.37));
    expect(wallet.ids, [7]);
    expect(wallet.keys, isEmpty);
    expect(find.text('฿100.37'), findsOneWidget);
    _lifecycle(tester, foreground: false);
    await tester.pump(const Duration(seconds: 15));
    expect(wallet.ids, [7]);
    _lifecycle(tester, foreground: true);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(wallet.ids, [7, 7]);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: isPlayChannel);

  testWidgets('direct missing QR on resume cannot silently create another bill', (tester) async {
    wallet.fail = true;
    await show(tester, resume: const ChatPendingBill(id: 7, ref: 'R7', amount: 100, payableAmount: 100.37));
    expect(find.text('โหลดบิลเดิมอีกครั้ง'), findsOneWidget);
    expect(find.text('฿100'), findsNothing);
    expect(wallet.keys, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: isPlayChannel);
}
