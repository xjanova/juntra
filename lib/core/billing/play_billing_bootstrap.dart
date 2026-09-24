import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../auth/session.dart';
import 'play_billing.dart';

/// ScaffoldMessenger กลางของแอพ — แจ้ง "เครดิตเข้าแล้ว" ได้จากทุกหน้า
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>(debugLabel: 'root-messenger');

/// เริ่มฟังการซื้อผ่าน Google Play ตั้งแต่เปิดแอพ (ช่อง Play เท่านั้น)
///
/// การซื้อที่จ่ายเสร็จตอนแอพถูกปิดไปก่อน / เน็ตหลุดหลังจ่าย / จ่ายแบบรอชำระแล้วเงินเข้าทีหลัง
/// จะถูกส่งมอบ (ยืนยันกับเซิร์ฟเวอร์ → เติมเครดิต) ทันทีที่เปิดแอพและล็อกอินอยู่ — ไม่ต้อง
/// รอให้ลูกค้าเข้าหน้าวอลเลต และต้องทันก่อนเส้น 3 วันที่ Google คืนเงินอัตโนมัติ
class PlayBillingBootstrap extends ConsumerStatefulWidget {
  const PlayBillingBootstrap({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<PlayBillingBootstrap> createState() => _PlayBillingBootstrapState();
}

class _PlayBillingBootstrapState extends ConsumerState<PlayBillingBootstrap> {
  StreamSubscription<BillingEvent>? _sub;

  @override
  void initState() {
    super.initState();
    final billing = ref.read(playBillingProvider);
    if (billing == null) return; // ช่อง APK — ไม่มี Google Play Billing
    billing.start();
    _sub = billing.events.listen(_onEvent);
    // ล็อกอินอยู่แล้วตอนเปิดแอพ หรือเพิ่งล็อกอิน/สลับบัญชี → เก็บตกการซื้อที่ค้าง
    ref.listenManual<String?>(sessionUserIdProvider, (prev, next) {
      if (next != null && next != prev) unawaited(billing.restorePending());
    }, fireImmediately: true);
  }

  void _onEvent(BillingEvent e) {
    if (e is! BillingCredited) return; // ข้อความอื่นแสดงโดยหน้าที่ลูกค้ากดซื้ออยู่
    final m = rootScaffoldMessengerKey.currentState;
    m?.hideCurrentSnackBar();
    m?.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: JuntraColors.bgPurpleDeep,
      content: Text('✨ ${e.message}', style: const TextStyle(color: JuntraColors.mintGreen)),
      duration: const Duration(seconds: 5),
    ));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
