import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/theme.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/wallet_repository.dart';
import '../../core/auth/auth_state.dart';

/// เติมเครดิตจบในแชท — สแกน QR จ่ายครั้งเดียวเหมือนบอท FB/LINE
///
/// เดิมแอพพาผู้ใช้ออกไปหน้าวอลเลตแล้วต้องเดินกลับมาเอง ซึ่งลูกค้ากลุ่มหลัก
/// (ผู้สูงอายุ) หลุดกลางทาง — เว็บแก้ไปแล้วรอบนี้แอพตามให้ทัน
///
/// เลข PromptPay + ยอดที่ต้องโอน (มีเศษสตางค์ไม่ซ้ำสำหรับจับคู่ SMS ธนาคาร)
/// มาจากเซิร์ฟเวอร์ทั้งหมด — แอพ **ห้ามคำนวณยอดหรือประกอบ QR เอง** เพราะ
/// เคยพลาดมาแล้วตอนที่ wallet_screen ทิ้ง payable_amount แล้วปัดเป็นยอดกลม
/// ทำให้ระบบเครดิตอัตโนมัติจับคู่ไม่ได้
class ChatTopUpSheet extends ConsumerStatefulWidget {
  const ChatTopUpSheet({super.key});

  /// คืน true เมื่อเติมเงินสำเร็จ เพื่อให้หน้าแชทปลดล็อกช่องพิมพ์ทันที
  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: JuntraColors.bgPurpleDeep,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => const ChatTopUpSheet(),
    );
  }

  @override
  ConsumerState<ChatTopUpSheet> createState() => _ChatTopUpSheetState();
}

class _ChatTopUpSheetState extends ConsumerState<ChatTopUpSheet> {
  static const _bundles = [50, 100, 200, 500];

  int? _txId;
  double? _payable;
  String? _qrPayload;
  String? _promptpayName;

  bool _busy = false;
  bool _paid = false;
  double? _balance;
  String? _error;
  String? _notice;

  Timer? _poll;
  int _waited = 0;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _choose(int amount) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final repo = await ref.read(walletRepositoryProvider.future);
      final res = await repo.startPromptPayTopup(amount: amount.toDouble());
      if (!mounted) return;

      // อ่านจากชั้นที่ backend ส่งมาจริง — เคยพลาดตรงนี้มาแล้ว (อ่าน top-level
      // ทั้งที่ค่าอยู่ใน promptpay) ทำให้ QR ว่างเปล่า
      final pp = (res['promptpay'] as Map?) ?? const {};
      setState(() {
        _txId = (res['id'] as num?)?.toInt()
            ?? ((res['transaction'] as Map?)?['id'] as num?)?.toInt();
        _payable = (res['payable_amount'] as num?)?.toDouble()
            ?? (res['amount'] as num?)?.toDouble();
        _qrPayload = (pp['qr_payload'] ?? res['qr_payload'])?.toString();
        _promptpayName = (pp['name'] ?? res['promptpay_name'])?.toString();
      });
      _startPolling();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'เครือข่ายมีปัญหาค่ะ ลองใหม่อีกครั้งนะคะ');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// ถามเซิร์ฟเวอร์เป็นระยะว่าเงินเข้าหรือยัง — หยุดเองที่ 10 นาที
  /// ไม่ปล่อยให้ยิงไม่จบถ้าผู้ใช้เปิดค้างไว้
  void _startPolling() {
    _poll?.cancel();
    _waited = 0;
    _poll = Timer.periodic(const Duration(seconds: 5), (t) async {
      _waited += 5;
      if (_waited > 600 || _txId == null) {
        t.cancel();
        return;
      }
      try {
        final repo = await ref.read(walletRepositoryProvider.future);
        final res = await repo.topupShow(_txId!);
        if (!mounted) return;
        if (res['status'] == 'success') {
          t.cancel();
          setState(() {
            _paid = true;
            _balance = (res['balance'] as num?)?.toDouble();
          });
          ref.read(authControllerProvider.notifier).refresh();
        }
      } catch (_) {
        // เน็ตสะดุดชั่วคราว — รอบหน้าลองใหม่
      }
    });
  }

  Future<void> _copyAmount() async {
    if (_payable == null) return;
    await Clipboard.setData(ClipboardData(text: _payable!.toStringAsFixed(2)));
    if (!mounted) return;
    setState(() => _notice = 'คัดลอกยอดแล้วค่ะ');
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  Future<void> _uploadSlip() async {
    if (_txId == null || _busy) return;

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (picked == null || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      final repo = await ref.read(walletRepositoryProvider.future);
      final res = await repo.uploadTopupSlip(
        transactionId: _txId!,
        filePath: picked.path,
        fileName: picked.name,
      );
      if (!mounted) return;

      // เซิร์ฟเวอร์ตรวจสลิปด้วย SlipOK ให้แล้ว — ถ้าผ่านจะเครดิตทันที
      if (res['paid'] == true) {
        _poll?.cancel();
        setState(() {
          _paid = true;
          _balance = (res['balance'] as num?)?.toDouble();
        });
        ref.read(authControllerProvider.notifier).refresh();
      } else {
        setState(() => _notice =
            res['message']?.toString() ?? 'ได้รับสลิปแล้วค่ะ ระบบกำลังตรวจสอบให้นะคะ');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'ส่งสลิปไม่สำเร็จค่ะ ลองใหม่อีกครั้งนะคะ');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20, 14, 20, MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: JuntraColors.gold.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            if (_paid) _done() else if (_qrPayload == null) _chooseAmount() else _payQr(),
          ],
        ),
      ),
    );
  }

  /* ── ขั้น 1: เลือกจำนวน ── */
  Widget _chooseAmount() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('เติมเครดิตเข้ากระเป๋า', style: baiJamjuree(size: 18, color: JuntraColors.gold)),
        const SizedBox(height: 6),
        const Text('เลือกจำนวนเงิน แล้วสแกน QR จ่ายได้เลยค่ะ',
            style: TextStyle(fontSize: 13, color: JuntraColors.textMuted)),
        const SizedBox(height: 18),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 2.4,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: _bundles
              .map((b) => _AmountButton(
                    amount: b,
                    enabled: !_busy,
                    onTap: () => _choose(b),
                  ))
              .toList(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFFF59999))),
        ],
      ],
    );
  }

  /* ── ขั้น 2: สแกนจ่าย ── */
  Widget _payQr() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('สแกนจ่ายได้เลยค่ะ', style: baiJamjuree(size: 18, color: JuntraColors.gold)),
        const SizedBox(height: 4),
        const Text('เปิดแอพธนาคาร → สแกน QR → โอนตามยอดด้านล่าง',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: JuntraColors.textMuted)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: QrImageView(
            data: _qrPayload!,
            size: 200,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 14),
        // ยอดต้องเป๊ะถึงสตางค์ — ระบบใช้เศษสตางค์จับคู่กับ SMS ธนาคาร
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          decoration: BoxDecoration(
            color: JuntraColors.gold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.6)),
          ),
          child: Column(
            children: [
              Text('฿${(_payable ?? 0).toStringAsFixed(2)}',
                  style: baiJamjuree(size: 28, color: JuntraColors.gold)),
              const SizedBox(height: 4),
              const Text('โอนยอดนี้ให้ตรงเป๊ะนะคะ ระบบจะเติมให้เองทันที',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: JuntraColors.textMuted)),
            ],
          ),
        ),
        if ((_promptpayName ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('เข้าบัญชี $_promptpayName',
              style: const TextStyle(fontSize: 12, color: JuntraColors.textMuted)),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            const SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: JuntraColors.gold),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _waited < 600
                    ? 'แม่หมอกำลังรอเงินเข้าอยู่ค่ะ...'
                    : 'ยังไม่พบเงินเข้า — แนบสลิปให้แม่หมอได้เลยค่ะ',
                style: const TextStyle(fontSize: 12.5, color: JuntraColors.textMuted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _copyAmount,
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('คัดลอกยอด', style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: JuntraColors.textLavender,
                  side: BorderSide(color: JuntraColors.gold.withValues(alpha: 0.35)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _uploadSlip,
                icon: const Icon(Icons.receipt_long, size: 16),
                label: Text(_busy ? 'กำลังส่ง...' : 'แนบสลิป',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                style: FilledButton.styleFrom(
                  backgroundColor: JuntraColors.gold,
                  foregroundColor: JuntraColors.bgPurpleDeep,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFFF59999))),
        ],
        if (_notice != null) ...[
          const SizedBox(height: 10),
          Text(_notice!, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF9EDDAE))),
        ],
      ],
    );
  }

  /* ── ขั้น 3: สำเร็จ ── */
  Widget _done() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: JuntraColors.mintGreen.withValues(alpha: 0.16),
            border: Border.all(color: JuntraColors.mintGreen, width: 2),
          ),
          child: const Icon(Icons.check, color: JuntraColors.mintGreen, size: 28),
        ),
        const SizedBox(height: 14),
        Text('เติมเครดิตสำเร็จแล้วค่ะ',
            style: baiJamjuree(size: 18, color: JuntraColors.gold)),
        const SizedBox(height: 6),
        Text(
          _balance == null
              ? 'คุยกับแม่หมอต่อได้เลยนะคะ'
              : 'ยอดคงเหลือ ฿${_balance!.toStringAsFixed(2)} — คุยกับแม่หมอต่อได้เลยค่ะ',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: JuntraColors.textMuted, height: 1.6),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: JuntraColors.gold,
              foregroundColor: JuntraColors.bgPurpleDeep,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('คุยกับแม่หมอต่อ',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}

class _AmountButton extends StatelessWidget {
  const _AmountButton({required this.amount, required this.enabled, required this.onTap});

  final int amount;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: JuntraColors.gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.3)),
            ),
            child: Text('฿$amount', style: baiJamjuree(size: 19, color: JuntraColors.textCream)),
          ),
        ),
      ),
    );
  }
}
