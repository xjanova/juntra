import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/billing/play_billing.dart';

/// ซื้อเครดิตผ่าน Google Play (แอพช่อง Play) — แทนหน้าเติมเงินพร้อมเพย์ของแอพ APK
///
/// นโยบาย Payments ของ Google Play: เครดิตที่ใช้ในแอพต้องขายผ่าน Google Play Billing และห้าม
/// ชี้ไปจ่ายช่องทางอื่น (ปุ่ม ลิงก์ ข้อความ QR) — ส่วนนี้จึงไม่มีการเอ่ยถึงพร้อมเพย์หรือเว็บเลย
/// เซิร์ฟเวอร์ปิดการขาย = แสดงแค่ว่าตอนนี้ยังไม่เปิดขายในแอพ (ใช้เครดิตที่มีได้ตามปกติ)
class PlayCreditsPanel extends ConsumerStatefulWidget {
  const PlayCreditsPanel({super.key, this.onCredited, this.compact = false});

  /// เครดิตเข้าแล้ว — ให้หน้าที่ถือแผงนี้อยู่รีเฟรชยอด
  final VoidCallback? onCredited;

  /// ใช้ในแผ่นเติมเครดิต (แชท/เครดิตไม่พอ) — ตัดหัวข้อใหญ่ออก
  final bool compact;

  @override
  ConsumerState<PlayCreditsPanel> createState() => _PlayCreditsPanelState();
}

class _PlayCreditsPanelState extends ConsumerState<PlayCreditsPanel> {
  PacksResult? _packs;
  bool _loading = true;
  String? _busyProduct;
  StreamSubscription<BillingEvent>? _sub;

  PlayBilling? get _billing => ref.read(playBillingProvider);

  @override
  void initState() {
    super.initState();
    final billing = _billing;
    if (billing != null) {
      billing.start();
      _sub = billing.events.listen(_onEvent);
    }
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final billing = _billing;
    if (billing == null) return;
    setState(() => _loading = true);
    final result = await billing.loadPacks();
    if (!mounted) return;
    setState(() {
      _packs = result;
      _loading = false;
    });
    // การซื้อที่จ่ายแล้วแต่ยังไม่ได้เครดิต (แอพปิด/เน็ตหลุดกลางทาง) — เก็บตกทุกครั้งที่เปิดหน้านี้
    if (result is PacksReady) unawaited(billing.restorePending());
  }

  Future<void> _buy(CreditPack pack) async {
    final billing = _billing;
    if (billing == null || _busyProduct != null) return; // กันกดรัว
    setState(() => _busyProduct = pack.productId);
    final launched = await billing.buy(pack);
    if (!mounted) return;
    if (!launched) setState(() => _busyProduct = null);
    // เปิดหน้าจ่ายสำเร็จ — ผลลัพธ์มาทาง events (สำเร็จ/ยกเลิก/รอชำระ/ผิดพลาด)
  }

  void _onEvent(BillingEvent e) {
    if (!mounted) return;
    setState(() => _busyProduct = null);
    final messenger = ScaffoldMessenger.maybeOf(context);
    switch (e) {
      case BillingCredited():
        // ข้อความ "เครดิตเข้าแล้ว" แสดงที่ PlayBillingBootstrap (ทั้งแอพ) — ที่นี่แค่รีเฟรชยอด
        widget.onCredited?.call();
      case BillingPending(:final message):
        _toast(messenger, message, JuntraColors.gold);
      case BillingFailed(:final message):
        _toast(messenger, message, const Color(0xFFFF8FA0));
      case BillingCanceled():
        break;
    }
  }

  void _toast(ScaffoldMessengerState? m, String text, Color accent) {
    m?.hideCurrentSnackBar();
    m?.showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: JuntraColors.bgPurpleDeep,
      content: Text(text, style: TextStyle(color: accent)),
      duration: const Duration(seconds: 5),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_billing == null) return const SizedBox.shrink();
    final header = widget.compact
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text('เติมเครดิต', style: baiJamjuree(size: 16, color: JuntraColors.gold)),
          );

    if (_loading) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        header,
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator(color: JuntraColors.gold)),
        ),
      ]);
    }

    final packs = _packs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        switch (packs) {
          PacksReady(:final packs) => _PackGrid(
              packs: packs,
              busyProduct: _busyProduct,
              onBuy: _buy,
            ),
          PacksDisabled() => const _Note(
              icon: Icons.info_outline,
              text: 'ขณะนี้ยังไม่เปิดขายเครดิตในแอพ — เครดิตที่มีอยู่ในบัญชีใช้ได้ตามปกติ',
            ),
          PacksUnavailable(:final message) => _Note(
              icon: Icons.cloud_off_outlined,
              text: message,
              action: TextButton(
                onPressed: _load,
                child: const Text('ลองอีกครั้ง', style: TextStyle(color: JuntraColors.gold)),
              ),
            ),
          null => const SizedBox.shrink(),
        },
        if (packs is PacksReady) ...[
          const SizedBox(height: 10),
          const Text(
            'ชำระผ่าน Google Play · เครดิตเข้าบัญชีทันทีหลังชำระเรียบร้อย',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: JuntraColors.textFaint, height: 1.5),
          ),
        ],
      ],
    );
  }
}

class _PackGrid extends StatelessWidget {
  const _PackGrid({required this.packs, required this.busyProduct, required this.onBuy});
  final List<CreditPack> packs;
  final String? busyProduct;
  final ValueChanged<CreditPack> onBuy;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.9,
      children: [
        for (final p in packs)
          _PackTile(
            pack: p,
            busy: busyProduct == p.productId,
            enabled: busyProduct == null,
            onTap: () => onBuy(p),
          ),
      ],
    );
  }
}

class _PackTile extends StatelessWidget {
  const _PackTile({required this.pack, required this.busy, required this.enabled, required this.onTap});
  final CreditPack pack;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final credits = pack.credits % 1 == 0 ? pack.credits.toInt().toString() : pack.credits.toString();
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(JuntraRadius.card),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: JuntraColors.purpleCardGradient,
          borderRadius: BorderRadius.circular(JuntraRadius.card),
          border: Border.all(color: JuntraColors.gold.withValues(alpha: busy ? 0.9 : 0.35)),
        ),
        child: busy
            ? const Center(
                child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: JuntraColors.gold)),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$credits เครดิต', style: baiJamjuree(size: 17, color: JuntraColors.textCream)),
                  const SizedBox(height: 4),
                  Text(pack.price, style: const TextStyle(fontSize: 13, color: JuntraColors.gold, fontWeight: FontWeight.w700)),
                ],
              ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        border: Border.all(color: JuntraColors.purple.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: JuntraColors.textMuted, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text, style: const TextStyle(fontSize: 13, color: JuntraColors.textLavender, height: 1.5)),
              ),
            ],
          ),
          ?action,
        ],
      ),
    );
  }
}

/// แผ่นเติมเครดิตผ่าน Google Play — ใช้จากแชทและแผ่น "เครดิตไม่พอ"
Future<void> showPlayCreditsSheet(BuildContext context, {VoidCallback? onCredited}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: JuntraColors.bgPurpleDeep,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: JuntraColors.gold.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('เติมเครดิต', style: baiJamjuree(size: 18, color: JuntraColors.gold)),
            const SizedBox(height: 12),
            PlayCreditsPanel(
              compact: true,
              onCredited: () {
                onCredited?.call();
                if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
              },
            ),
          ],
        ),
      ),
    ),
  );
}
