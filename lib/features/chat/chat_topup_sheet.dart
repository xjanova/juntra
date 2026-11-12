import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/theme.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/chat_repository.dart';
import '../../core/api/wallet_repository.dart';
import '../../core/app_channel.dart';
import '../../core/auth/auth_state.dart';
import '../../core/auth/session.dart';
import '../../core/api/idempotency.dart';

/// เติมเครดิตจบในแชท — สแกน QR จ่ายครั้งเดียวเหมือนบอท FB/LINE
///
/// เดิมแอพพาผู้ใช้ออกไปหน้าวอลเลตแล้วต้องเดินกลับมาเอง ซึ่งลูกค้ากลุ่มหลัก
/// (ผู้สูงอายุ) หลุดกลางทาง — เว็บแก้ไปแล้วรอบนี้แอพตามให้ทัน
///
/// เลข PromptPay + ยอดที่ต้องโอน (มีเศษสตางค์ไม่ซ้ำสำหรับจับคู่ SMS ธนาคาร)
/// มาจากเซิร์ฟเวอร์ทั้งหมด — แอพ **ห้ามคำนวณยอดหรือประกอบ QR เอง** เพราะ
/// เคยพลาดมาแล้วตอนที่ wallet_screen ทิ้ง payable_amount แล้วปัดเป็นยอดกลม
/// ทำให้ระบบเครดิตอัตโนมัติจับคู่ไม่ได้
///
/// 🛡 ช่อง Google Play เปิดชีทนี้ไม่ได้เด็ดขาด (นโยบาย Payments) — [show] คืน false ทันที
/// หน้าแชทช่อง Play ใช้ `showPlayCreditsSheet` แทน
// ตัวเลขเงินจาก Laravel อาจมาเป็นสตริง (cast decimal) — `as num?` จะ throw กลางหน้าจ่ายเงิน
double? _toDouble(Object? v) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
Map _asMap(Object? v) => v is Map ? v : const {};

class ChatTopUpSheet extends ConsumerStatefulWidget {
  const ChatTopUpSheet({super.key, this.resume, this.selfName = 'แม่หมอ'});

  /// บิลค้างของห้อง ("ดู QR จ่ายต่อ") — เปิดรายการเดิมต่อ ไม่สร้างรายการใหม่
  final ChatPendingBill? resume;

  /// ผู้พยากรณ์ของห้อง (ปุ่ม "คุยกับ…ต่อ")
  final String selfName;

  /// คืน true เมื่อเติมเงินสำเร็จ เพื่อให้หน้าแชทปลดล็อกช่องพิมพ์ทันที
  static Future<bool?> show(
    BuildContext context, {
    ChatPendingBill? resume,
    String selfName = 'แม่หมอ',
  }) {
    if (isPlayChannel) return Future.value(false);
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: JuntraColors.bgPurpleDeep,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => ChatTopUpSheet(resume: resume, selfName: selfName),
    );
  }

  @override
  ConsumerState<ChatTopUpSheet> createState() => _ChatTopUpSheetState();
}

class _ChatTopUpSheetState extends ConsumerState<ChatTopUpSheet>
    with WidgetsBindingObserver {
  /// ชุดยอดเดิมของแอพ — ใช้เมื่อเซิร์ฟเวอร์ยังไม่ส่ง `topup.bundles` (เซิร์ฟเวอร์เก่า/ยังโหลดอยู่)
  static const _legacyBundles = [50, 100, 200, 500];

  /// กันสร้างรายการเติมเงินซ้ำเมื่อสัญญาณหลุดแล้วแอพ/ผู้ใช้ส่งซ้ำ — ผูกกับยอดที่กด
  /// (เดิมหน้านี้ไม่ส่งคีย์เลย ต่างจากหน้าวอลเลต)
  final _attempt = IdempotentAttempt('chat-topup');

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
  Timer? _noticeTimer;
  DateTime? _pollUntil;
  bool _foreground = true;
  bool _pollBusy = false;
  int _epoch = 0;

  bool _valid(int epoch) => mounted && epoch == _epoch && !isPlayChannel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (isPlayChannel) return;
    final bill = widget.resume;
    if (bill != null) {
      // วาด QR ของบิลเดิมได้ทันที แล้วค่อยถามสถานะล่าสุด (อาจจ่ายแล้ว/หมดอายุแล้ว)
      _txId = bill.id;
      _payable = bill.payableAmount;
      _qrPayload = bill.qrPayload;
      if (bill.hasSlip) _notice = 'ได้รับสลิปแล้วค่ะ ระบบกำลังตรวจสอบให้นะคะ';
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshResumed());
    }
  }

  /// สถานะล่าสุดของบิลที่เปิดต่อ — จ่ายแล้วโชว์สำเร็จ · ไม่ค้างแล้วให้เลือกยอดใหม่
  Future<void> _refreshResumed() async {
    final id = _txId;
    final epoch = _epoch;
    if (id == null || !_valid(epoch)) return;
    setState(() => _busy = true);
    try {
      final repo = await ref.read(walletRepositoryProvider.future);
      if (!_valid(epoch)) return;
      final res = await repo.topupShow(id);
      if (!_valid(epoch)) return;
      final status = res['status']?.toString();
      final pp = _asMap(res['promptpay']);
      setState(() {
        if (status == 'success') {
          _paid = true;
          _balance = _toDouble(res['balance']);
        } else if (status != null && status != 'pending') {
          // หมดอายุ/ยกเลิกไปแล้ว — ไม่ให้สแกน QR ของบิลที่ใช้ไม่ได้
          _txId = null;
          _qrPayload = null;
          _payable = null;
          _notice = null;
          _pollUntil = null;
          _error = 'บิลนี้ใช้ไม่ได้แล้วค่ะ เลือกยอดใหม่ได้เลยนะคะ';
        } else {
          _payable = _toDouble(res['payable_amount']) ?? _payable;
          _qrPayload =
              (pp['qr_payload'] ?? res['qr_payload'])?.toString() ?? _qrPayload;
          _promptpayName = (pp['name'] ?? res['promptpay_name'])?.toString();
          if (res['slip_uploaded'] == true) {
            _notice = 'ได้รับสลิปแล้วค่ะ ระบบกำลังตรวจสอบให้นะคะ';
          }
        }
      });
      if (_paid) {
        ref.read(authControllerProvider.notifier).refresh();
      } else if (_txId != null && _qrPayload != null) {
        _startPolling();
      }
    } on ApiException catch (e) {
      if (!_valid(epoch)) return;
      setState(() => _error = e.message);
      if (_qrPayload != null) _startPolling();
    } catch (_) {
      if (!_valid(epoch)) return;
      // เน็ตสะดุด — ยังสแกน QR ของบิลเดิมได้ และรอบ poll ถามสถานะต่อเอง
      if (_qrPayload != null) _startPolling();
    } finally {
      if (_valid(epoch)) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _epoch++;
    _poll?.cancel();
    _noticeTimer?.cancel();
    super.dispose();
  }

  Future<void> _choose(int amount) async {
    final epoch = _epoch;
    if (_busy || !_valid(epoch)) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final repo = await ref.read(walletRepositoryProvider.future);
      if (!_valid(epoch)) return;
      final res = await repo.startPromptPayTopup(
        amount: amount.toDouble(),
        idempotencyKey: _attempt.begin('$amount'),
      );
      _attempt.succeeded();
      if (!_valid(epoch)) return;

      // อ่านจากชั้นที่ backend ส่งมาจริง — เคยพลาดตรงนี้มาแล้ว (อ่าน top-level
      // ทั้งที่ค่าอยู่ใน promptpay) ทำให้ QR ว่างเปล่า
      final pp = _asMap(res['promptpay']);
      setState(() {
        _txId =
            _toDouble(res['id'])?.toInt() ??
            _toDouble(_asMap(res['transaction'])['id'])?.toInt();
        _payable =
            _toDouble(res['payable_amount']) ?? _toDouble(res['amount']);
        _qrPayload = (pp['qr_payload'] ?? res['qr_payload'])?.toString();
        _promptpayName = (pp['name'] ?? res['promptpay_name'])?.toString();
      });
      // บิลใหม่ได้เวลารอเงินเข้าเต็ม 10 นาทีของตัวเอง (ไม่ใช่เวลาที่เหลือของบิลก่อน)
      _pollUntil = null;
      _startPolling();
    } on ApiException catch (e) {
      if (_valid(epoch)) setState(() => _error = e.message);
    } catch (_) {
      if (_valid(epoch)) {
        setState(() => _error = 'เครือข่ายมีปัญหาค่ะ ลองใหม่อีกครั้งนะคะ');
      }
    } finally {
      if (_valid(epoch)) setState(() => _busy = false);
    }
  }

  /// ถามเซิร์ฟเวอร์เป็นระยะว่าเงินเข้าหรือยัง — หยุดเองที่ 10 นาที
  /// ไม่ปล่อยให้ยิงไม่จบถ้าผู้ใช้เปิดค้างไว้
  void _startPolling() {
    _poll?.cancel();
    if (!mounted || isPlayChannel || !_foreground || _paid || _txId == null) {
      return;
    }
    _pollUntil ??= DateTime.now().add(const Duration(minutes: 10));
    if (DateTime.now().isAfter(_pollUntil!)) return;
    _poll = Timer(const Duration(seconds: 5), _pollStatus);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _startPolling();
    } else {
      _poll?.cancel();
    }
  }

  Future<void> _pollStatus() async {
    final epoch = _epoch;
    final id = _txId;
    if (!_valid(epoch) || !_foreground || id == null || _paid) return;
    if (_pollBusy || _busy) {
      _startPolling();
      return;
    }
    _pollBusy = true;
    try {
      final repo = await ref.read(walletRepositoryProvider.future);
      if (!_valid(epoch)) return;
      final res = await repo.topupShow(id);
      if (!_valid(epoch)) return;
      if (res['status'] == 'success') {
        setState(() {
          _paid = true;
          _balance = _toDouble(res['balance']);
        });
        ref.read(authControllerProvider.notifier).refresh();
      } else if (res['status'] != null && res['status'] != 'pending') {
        setState(() {
          _txId = null;
          _qrPayload = null;
          _error = 'บิลนี้ใช้ไม่ได้แล้วค่ะ เลือกยอดใหม่ได้เลยนะคะ';
          _pollUntil = null;
        });
      }
    } catch (_) {
      // เน็ตสะดุดชั่วคราว — รอบหน้าลองใหม่
    } finally {
      _pollBusy = false;
    }
    if (_valid(epoch)) _startPolling();
  }

  Future<void> _copyAmount() async {
    if (_payable == null) return;
    final epoch = _epoch;
    await Clipboard.setData(ClipboardData(text: _payable!.toStringAsFixed(2)));
    if (!_valid(epoch)) return;
    setState(() => _notice = 'คัดลอกยอดแล้วค่ะ');
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 2), () {
      if (_valid(epoch)) setState(() => _notice = null);
    });
  }

  Future<void> _uploadSlip() async {
    final epoch = _epoch;
    final id = _txId;
    if (id == null || _busy || !_valid(epoch)) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (picked == null || !_valid(epoch)) return;
      final repo = await ref.read(walletRepositoryProvider.future);
      if (!_valid(epoch)) return;
      final res = await repo.uploadTopupSlip(
        transactionId: id,
        filePath: picked.path,
        fileName: picked.name,
      );
      if (!_valid(epoch)) return;

      // เซิร์ฟเวอร์ตรวจสลิปด้วย SlipOK ให้แล้ว — ถ้าผ่านจะเครดิตทันที
      if (res['paid'] == true) {
        _poll?.cancel();
        setState(() {
          _paid = true;
          _balance = _toDouble(res['balance']);
        });
        ref.read(authControllerProvider.notifier).refresh();
      } else {
        setState(
          () => _notice =
              res['message']?.toString() ??
              'ได้รับสลิปแล้วค่ะ ระบบกำลังตรวจสอบให้นะคะ',
        );
      }
    } on ApiException catch (e) {
      if (_valid(epoch)) setState(() => _error = e.message);
    } catch (_) {
      if (_valid(epoch)) {
        setState(() => _error = 'ส่งสลิปไม่สำเร็จค่ะ ลองใหม่อีกครั้งนะคะ');
      }
    } finally {
      if (_valid(epoch)) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isPlayChannel) return const SizedBox.shrink();
    ref.listen<String?>(sessionUserIdProvider, (before, after) {
      if (before == after) return;
      _epoch++;
      _poll?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(false);
      });
    });
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          14,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: JuntraColors.gold.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            if (_paid)
              _done()
            else if (_txId != null && _qrPayload == null)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('กำลังเปิดบิลเดิมของคุณค่ะ'),
                  if (_error != null) Text(_error!),
                  TextButton(
                    onPressed: _busy ? null : _refreshResumed,
                    child: Text(_busy ? 'กำลังโหลด…' : 'โหลดบิลเดิมอีกครั้ง'),
                  ),
                ],
              )
            else if (_qrPayload == null)
              _chooseAmount()
            else
              _payQr(),
          ],
        ),
      ),
    );
  }

  /* ── ขั้น 1: เลือกจำนวน ── */
  Widget _chooseAmount() {
    // ชุดยอดเดียวกับหน้าเติมเงินของเว็บ (`GET /v1/wallet` → topup.bundles)
    final cfg = ref.watch(walletTopupConfigProvider).valueOrNull;
    final bundles = (cfg != null && cfg.fromServer)
        ? cfg.bundles
        : _legacyBundles;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'เติมเครดิตเข้ากระเป๋า',
          style: baiJamjuree(size: 18, color: JuntraColors.gold),
        ),
        const SizedBox(height: 6),
        const Text(
          'เลือกจำนวนเงิน แล้วสแกน QR จ่ายได้เลยค่ะ',
          style: TextStyle(fontSize: 13, color: JuntraColors.textMuted),
        ),
        const SizedBox(height: 18),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 2.4,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: bundles
              .map(
                (b) => _AmountButton(
                  amount: b,
                  enabled: !_busy,
                  onTap: () => _choose(b),
                ),
              )
              .toList(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFFF59999)),
          ),
        ],
      ],
    );
  }

  /* ── ขั้น 2: สแกนจ่าย ── */
  Widget _payQr() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'สแกนจ่ายได้เลยค่ะ',
          style: baiJamjuree(size: 18, color: JuntraColors.gold),
        ),
        const SizedBox(height: 4),
        const Text(
          'เปิดแอพธนาคาร → สแกน QR → โอนตามยอดด้านล่าง',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: JuntraColors.textMuted),
        ),
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
              Text(
                '฿${(_payable ?? 0).toStringAsFixed(2)}',
                style: baiJamjuree(size: 28, color: JuntraColors.gold),
              ),
              const SizedBox(height: 4),
              const Text(
                'โอนยอดนี้ให้ตรงเป๊ะนะคะ ระบบจะเติมให้เองทันที',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: JuntraColors.textMuted),
              ),
            ],
          ),
        ),
        if ((_promptpayName ?? '').isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'เข้าบัญชี $_promptpayName',
            style: const TextStyle(fontSize: 12, color: JuntraColors.textMuted),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: JuntraColors.gold,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _pollUntil == null || DateTime.now().isBefore(_pollUntil!)
                    ? 'ระบบกำลังรอเงินเข้าอยู่ค่ะ...'
                    : 'ยังไม่พบเงินเข้า — แนบสลิปได้เลยค่ะ',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: JuntraColors.textMuted,
                ),
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
                  side: BorderSide(
                    color: JuntraColors.gold.withValues(alpha: 0.35),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _uploadSlip,
                icon: const Icon(Icons.receipt_long, size: 16),
                label: Text(
                  _busy ? 'กำลังส่ง...' : 'แนบสลิป',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: JuntraColors.gold,
                  foregroundColor: JuntraColors.bgPurpleDeep,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFFF59999)),
          ),
        ],
        if (_notice != null) ...[
          const SizedBox(height: 10),
          Text(
            _notice!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF9EDDAE)),
          ),
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
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: JuntraColors.mintGreen.withValues(alpha: 0.16),
            border: Border.all(color: JuntraColors.mintGreen, width: 2),
          ),
          child: const Icon(
            Icons.check,
            color: JuntraColors.mintGreen,
            size: 28,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'เติมเครดิตสำเร็จแล้วค่ะ',
          style: baiJamjuree(size: 18, color: JuntraColors.gold),
        ),
        const SizedBox(height: 6),
        Text(
          _balance == null
              ? 'คุยกับ${widget.selfName}ต่อได้เลยนะคะ'
              : 'ยอดคงเหลือ ฿${_balance!.toStringAsFixed(2)} — คุยกับ${widget.selfName}ต่อได้เลยค่ะ',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: JuntraColors.textMuted,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: JuntraColors.gold,
              foregroundColor: JuntraColors.bgPurpleDeep,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              // แตะซ้ำก่อนชีทปิดเสร็จ = pop ครั้งที่สองไปโดนหน้าแชทข้างล่าง
              if (ModalRoute.of(context)?.isCurrent ?? false) {
                Navigator.of(context).pop(true);
              }
            },
            child: Text(
              'คุยกับ${widget.selfName}ต่อ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

class _AmountButton extends StatelessWidget {
  const _AmountButton({
    required this.amount,
    required this.enabled,
    required this.onTap,
  });

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
              border: Border.all(
                color: JuntraColors.gold.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              '฿$amount',
              style: baiJamjuree(size: 19, color: JuntraColors.textCream),
            ),
          ),
        ),
      ),
    );
  }
}
