import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/idempotency.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/wallet_repository.dart';
import '../../core/payments/promptpay_qr.dart';
import '../../core/auth/auth_state.dart';
import '../../shared/widgets/gold_button.dart';
import '../../shared/widgets/starry_background.dart';

/// วอลเลต — credit balance, top-up start, recent transactions.
///
/// Top-up flow:
///   1. User taps an amount → POST /wallet/topup/promptpay returns the
///      receiving info + a pending tx id.
///   2. A bottom sheet shows PromptPay receiver name + ID. The user
///      switches apps to their bank, pays externally, then returns
///      and either:
///         (a) taps "ถ่ายรูปสลิป" (camera via image_picker) OR
///         (b) taps "เลือกจากแกลเลอรี" (gallery)
///      and the picked image POSTs to /wallet/topup/{tx}/slip
///      (multipart). On success the sheet closes and the wallet
///      refreshes — admin approval still happens via Filament.
///   3. Fallback: "เปิดเว็บแทน" links to the legacy `slip_upload_url`
///      so a user on a device with broken image_picker plugins can
///      still finish via the browser.
class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});
  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  Future<Map<String, dynamic>>? _overview;

  /// กันกดปุ่มจำนวนเงินรัว ๆ — ระหว่างรอ POST ไม่มี feedback ใด ๆ ผู้ใช้จึงกด
  /// ซ้ำเป็นเรื่องปกติ ได้รายการค้างหลายใบยอดคนละเศษสตางค์ จนไม่รู้ว่าต้องโอน
  /// ใบไหน และครบเพดาน 5 ใบแล้วสร้างใหม่ไม่ได้ (ชีทเติมเงินในแชททำถูกมาตลอด)
  bool _startingTopup = false;

  /// คีย์กันสร้างรายการเติมเงินซ้ำ — ผูกกับยอดที่กด
  final _topupAttempt = IdempotentAttempt('topup');

  @override
  void initState() {
    super.initState();
    _overview = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final repo = await ref.read(walletRepositoryProvider.future);
    return repo.overview();
  }

  Future<void> _refresh() async {
    // ผู้ใช้กดยกเลิกรายการแล้วออกจากหน้านี้ระหว่างที่ยัง await อยู่ได้ —
    // setState หลัง dispose = แครช เช็ค mounted คร่อมทุก await ให้ครบ
    // (เมธอดนี้ถูกเรียกจาก 3 จุด การกันที่นี่จึงคุ้มกว่าไปกันทีละจุด)
    if (!mounted) return;
    setState(() => _overview = _load());
    await _overview;
    if (!mounted) return;
    // Update auth state's cached balance too so the home greeting matches.
    await ref.read(authControllerProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const StarryBackground(density: 30, intensity: 0.4),
          SafeArea(
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: JuntraColors.gold,
              backgroundColor: JuntraColors.bgPurpleDeep,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _Header(onBack: () => context.canPop()
                      ? context.pop()
                      : context.go(Routes.profile)),
                  const SizedBox(height: 12),
                  FutureBuilder<Map<String, dynamic>>(
                    future: _overview,
                    builder: (_, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(40),
                          child: Center(child: CircularProgressIndicator(
                            color: JuntraColors.gold,
                          )),
                        );
                      }
                      if (snap.hasError || !snap.hasData) {
                        return _ErrorState(
                          message: snap.error is ApiException
                              ? (snap.error as ApiException).message
                              : 'ไม่สามารถโหลดข้อมูลวอลเลตได้',
                          onRetry: _refresh,
                        );
                      }
                      final data = snap.data!;
                      final balance = (data['balance'] as num?)?.toDouble() ?? 0;
                      final currency = data['currency']?.toString() ?? 'THB';
                      final pricing = (data['pricing'] as Map?) ?? const {};
                      final txs =
                          (data['recent_transactions'] as List?)?.cast<Map>() ?? const [];
                      return Column(
                        children: [
                          _BalanceCard(balance: balance, currency: currency),
                          const SizedBox(height: 14),
                          _TopupRow(
                            enabled: !_startingTopup,
                            onPick: (amount) => _startTopup(amount),
                          ),
                          const SizedBox(height: 18),
                          _PricingHint(pricing: pricing.cast<String, dynamic>()),
                          const SizedBox(height: 18),
                          if (txs.isNotEmpty) ...[
                            const _SectionLabel('รายการล่าสุด'),
                            const SizedBox(height: 8),
                            for (final t in txs)
                              _TxTile(
                                tx: t.cast<String, dynamic>(),
                                onReupload: () =>
                                    _reuploadSlip(t.cast<String, dynamic>()),
                                onCancel: () =>
                                    _cancelTopup(t.cast<String, dynamic>()),
                              ),
                            const SizedBox(height: 10),
                            Center(
                              child: TextButton(
                                onPressed: () => context.push(Routes.transactions),
                                child: const Text('ดูประวัติทั้งหมด →',
                                    style: TextStyle(color: JuntraColors.gold, fontSize: 13)),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startTopup(double amount) async {
    if (_startingTopup) return;
    setState(() => _startingTopup = true);

    final Map<String, dynamic> initiated;
    try {
      final repo = await ref.read(walletRepositoryProvider.future);
      initiated = await repo.startPromptPayTopup(
        amount: amount,
        // ยอดเดียวกัน = รายการเดียวกัน ถึง dio จะ retry ให้เองก็ไม่เกิดใบซ้ำ
        idempotencyKey: _topupAttempt.begin('topup-${amount.toStringAsFixed(2)}'),
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _startingTopup = false);
        _toast(e.message);
      }
      return;
    } catch (_) {
      if (mounted) {
        setState(() => _startingTopup = false);
        _toast('สร้างรายการไม่สำเร็จ กรุณาลองใหม่');
      }
      return;
    } finally {
      // ปลดล็อกทันทีที่รู้ผล — ชีทที่เปิดต่อจากนี้มี guard ของตัวเองอยู่แล้ว
      if (mounted && _startingTopup) setState(() => _startingTopup = false);
    }
    if (!mounted) return;
    _topupAttempt.succeeded();   // สร้างสำเร็จแล้ว รอบหน้าเป็นรายการใหม่
    final txMap = (initiated['transaction'] as Map?)?.cast<String, dynamic>()
        ?? const {};
    final txId = (txMap['id'] as num?)?.toInt();
    if (txId == null) {
      _toast('สร้างรายการไม่สำเร็จ — ไม่ได้รับเลขที่รายการ');
      return;
    }
    // CRITICAL for SMS-checker auto-credit: when enabled, the backend reserves
    // a UNIQUE payable amount (e.g. ฿100.37) and returns the exact EMVCo
    // `qr_payload` carrying it. The user MUST pay that exact figure (and scan
    // that exact QR) or the incoming bank SMS won't match the reservation.
    // Fall back to the round amount only when the backend didn't reserve one.
    final payable = (initiated['payable_amount'] as num?)?.toDouble()
        ?? (txMap['amount'] as num?)?.toDouble()
        ?? amount;
    final promptpay =
        (initiated['promptpay'] as Map?)?.cast<String, dynamic>() ?? const {};
    await _openTopupSheet(
      txId: txId,
      amount: payable,
      promptpay: promptpay,
      slipUploadUrl: initiated['slip_upload_url']?.toString(),
      // qr_payload is nested INSIDE promptpay (data.promptpay.qr_payload), not
      // top-level — read it from there so the backend's exact reserved-amount
      // QR is used instead of a locally rebuilt one.
      qrPayload: promptpay['qr_payload']?.toString(),
      instructions: initiated['instructions']?.toString(),
      autoConfirm: initiated['auto_confirm'] == true,
    );
    // After the sheet closes either with a successful upload or a
    // dismissal, refresh so the new pending tx (or freshly-uploaded
    // one) shows up in the recent-transactions list.
    await _refresh();
  }

  Future<void> _openTopupSheet({
    required int txId,
    required double amount,
    required Map<String, dynamic> promptpay,
    String? slipUploadUrl,
    String? qrPayload,
    String? instructions,
    bool autoConfirm = false,
  }) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: JuntraColors.bgPurpleDeep,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => _TopupSheet(
        txId: txId,
        amount: amount,
        promptpayId: promptpay['id']?.toString() ?? '',
        promptpayName: promptpay['name']?.toString() ?? '',
        webFallbackUrl: slipUploadUrl,
        qrPayload: qrPayload,
        instructions: instructions,
        autoConfirm: autoConfirm,
        onUploaded: () {
          if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
        },
      ),
    );
  }

  /// Re-open the slip sheet for an already-pending top-up so a user who
  /// dismissed it (or picked the wrong image) can upload again. We re-fetch
  /// the tx so the PromptPay receiver info + web fallback are current; the
  /// backend allows overwriting the slip while the tx is still pending.
  Future<void> _reuploadSlip(Map<String, dynamic> tx) async {
    final txId = (tx['id'] as num?)?.toInt();
    if (txId == null) {
      _toast('ไม่พบเลขที่รายการ — กรุณารีเฟรชแล้วลองใหม่');
      return;
    }
    final amount = ((tx['amount'] as num?)?.toDouble() ?? 0).abs();
    Map<String, dynamic> show;
    try {
      final repo = await ref.read(walletRepositoryProvider.future);
      show = await repo.topupShow(txId);
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
      return;
    } catch (_) {
      // Defensive: an unexpected body shape surfaces as a cast error, not an
      // ApiException — don't let the tap fail silently on the money flow.
      if (mounted) _toast('เปิดรายการไม่สำเร็จ — กรุณาลองใหม่');
      return;
    }
    if (!mounted) return;
    final promptpay =
        (show['promptpay'] as Map?)?.cast<String, dynamic>() ?? const {};
    final payable = (show['payable_amount'] as num?)?.toDouble() ?? amount;
    await _openTopupSheet(
      txId: txId,
      amount: payable,
      promptpay: promptpay,
      slipUploadUrl: show['slip_upload_url']?.toString(),
      // topupShow now returns the promptpay/QR block — render it on re-upload.
      qrPayload: promptpay['qr_payload']?.toString(),
    );
    await _refresh();
  }

  /// Cancel a pending top-up (releases the reserved amount). Confirms first —
  /// it's destructive (the user can't un-cancel).
  Future<void> _cancelTopup(Map<String, dynamic> tx) async {
    final txId = (tx['id'] as num?)?.toInt();
    if (txId == null) {
      _toast('ไม่พบเลขที่รายการ — กรุณารีเฟรชแล้วลองใหม่');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: JuntraColors.bgPurpleDeep,
        title: Text('ยกเลิกรายการเติมเงิน?',
            style: baiJamjuree(size: 18, color: JuntraColors.gold)),
        content: const Text(
          'รายการที่รออนุมัตินี้จะถูกยกเลิก — ทำได้เฉพาะกรณียังไม่ได้โอนเงิน',
          style: TextStyle(color: JuntraColors.textLavender, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('ไม่ยกเลิก',
                style: TextStyle(color: JuntraColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('ยกเลิกรายการ',
                style: TextStyle(color: Color(0xFFFF8FA0))),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final repo = await ref.read(walletRepositoryProvider.future);
      await repo.cancelTopup(txId);
      if (mounted) _toast('ยกเลิกรายการเติมเงินแล้ว');
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    } catch (_) {
      if (mounted) _toast('ยกเลิกไม่สำเร็จ — กรุณาลองใหม่');
    }
    await _refresh();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: JuntraColors.bgPurpleDeep,
      behavior: SnackBarBehavior.floating,
    ));
  }
}

/* ─── Sub-widgets ───────────────────────────────────────────── */

class _Header extends StatelessWidget {
  const _Header({required this.onBack});
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, color: JuntraColors.gold, size: 28),
          onPressed: onBack,
        ),
        Expanded(
          child: Text('วอลเลต',
              style: baiJamjuree(size: 20),
              textAlign: TextAlign.center),
        ),
        const SizedBox(width: 40),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance, required this.currency});
  final double balance;
  final String currency;
  @override
  Widget build(BuildContext context) {
    final symbol = currency == 'THB' ? '฿' : currency;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: JuntraColors.purpleCardGradient,
        borderRadius: BorderRadius.circular(JuntraRadius.hero),
        border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.4)),
        boxShadow: const [
          BoxShadow(color: Color(0x99000000), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ยอดเครดิตคงเหลือ',
              style: TextStyle(
                fontSize: 11, letterSpacing: 1.6,
                color: JuntraColors.textFaint,
              )),
          const SizedBox(height: 8),
          ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              colors: [Color(0xFFFFE7A0), Color(0xFFF0C75E), Color(0xFFB8881F)],
            ).createShader(rect),
            child: Text(
              '$symbol${NumberFormat.decimalPattern('th').format(balance)}',
              style: baiJamjuree(size: 38, color: Colors.white),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'ใช้สำหรับเปิดไพ่ ทำนาย และสนทนากับแม่หมอ',
            style: TextStyle(fontSize: 12, color: JuntraColors.textMuted),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1);
  }
}

class _TopupRow extends StatelessWidget {
  const _TopupRow({required this.onPick, this.enabled = true});
  final ValueChanged<double> onPick;
  final bool enabled;
  // Matches config/pricing.php `topup_bundles` on the backend.
  static const _options = <double>[50, 100, 200, 500, 1000, 2000];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('เติมเครดิต',
            style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600,
              color: JuntraColors.textCream,
            )),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (_, c) {
            final tileW = (c.maxWidth - 16) / 3; // 3 per row, 8px gaps
            return Wrap(
              spacing: 8, runSpacing: 8,
              children: [
                for (final amt in _options)
                  SizedBox(
                    width: tileW,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(JuntraRadius.card),
                      onTap: enabled ? () => onPick(amt) : null,
                      child: Opacity(
                        opacity: enabled ? 1 : 0.45,
                        child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: JuntraColors.mysticHeroGradient,
                          borderRadius: BorderRadius.circular(JuntraRadius.card),
                          border: Border.all(
                            color: JuntraColors.gold.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text('฿${amt.toInt()}',
                            style: baiJamjuree(size: 16, color: JuntraColors.gold)),
                      ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 6),
        const Text(
          'โอนตามจำนวนให้ตรงเป๊ะ ๆ · เติมขั้นต่ำ ฿20 · ระบบเครดิตอัตโนมัติเมื่อเงินเข้า หรืออัปโหลดสลิปให้แอดมินอนุมัติ',
          style: TextStyle(fontSize: 11, color: JuntraColors.textFaint, height: 1.5),
        ),
      ],
    );
  }
}

/// Bottom sheet that opens after the user has picked a top-up amount.
/// Shows PromptPay receiver info + camera/gallery pickers + a web
/// fallback link. On a successful slip upload it calls [onUploaded]
/// (which the parent uses to pop the sheet) so the parent's _refresh()
/// can run with the fresh slip_path persisted server-side.
class _TopupSheet extends ConsumerStatefulWidget {
  const _TopupSheet({
    required this.txId,
    required this.amount,
    required this.promptpayId,
    required this.promptpayName,
    required this.onUploaded,
    this.webFallbackUrl,
    this.qrPayload,
    this.instructions,
    this.autoConfirm = false,
  });
  final int txId;
  final double amount;
  final String promptpayId;
  final String promptpayName;
  final String? webFallbackUrl;
  /// Exact EMVCo payload reserved by the backend (carries the unique payable
  /// amount). When present we render THIS, not a locally-rebuilt QR.
  final String? qrPayload;
  /// Backend-provided instruction copy (auto-credit vs manual approval).
  final String? instructions;
  /// True when SMS-checker auto-credit is on — payment is confirmed
  /// automatically once the matching bank SMS arrives.
  final bool autoConfirm;
  final VoidCallback onUploaded;

  @override
  ConsumerState<_TopupSheet> createState() => _TopupSheetState();
}

class _TopupSheetState extends ConsumerState<_TopupSheet> {
  final _picker = ImagePicker();
  bool _uploading = false;
  String? _errorMsg;

  /// เช็คเงินเข้าเป็นระยะเมื่อเปิดโหมดเครดิตอัตโนมัติ
  ///
  /// 🔴 ชีทนี้เขียนป้ายไว้เองว่า "ระบบจะเติมเครดิตให้อัตโนมัติทันทีที่เงินเข้า"
  /// แต่ไม่เคย poll เลย ลูกค้าโอนเสร็จนั่งมองชีทที่ไม่ขยับ ต้องเดาเองว่าปิดแล้ว
  /// ลากรีเฟรช — ขณะที่ชีทเติมเงินในแชททำถูกมาตลอด ผู้ใช้จึงเจอสองพฤติกรรม
  /// ในแอพเดียว
  Timer? _poll;
  int _waited = 0;
  bool _paid = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoConfirm) _startPolling();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _poll?.cancel();
    _waited = 0;
    _poll = Timer.periodic(const Duration(seconds: 5), (t) async {
      _waited += 5;
      // หยุดเองที่ 10 นาที ไม่ปล่อยให้ยิงไม่จบถ้าผู้ใช้เปิดค้างไว้
      if (_waited > 600) {
        t.cancel();
        return;
      }
      try {
        final repo = await ref.read(walletRepositoryProvider.future);
        final res = await repo.topupShow(widget.txId);
        if (!mounted) return;
        if (res['status'] == 'success') {
          t.cancel();
          setState(() => _paid = true);
          // ignore: unawaited_futures
          ref.read(authControllerProvider.notifier).refresh();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('เติมเครดิตสำเร็จแล้วค่ะ ✨'),
            backgroundColor: JuntraColors.bgPurpleDeep,
            behavior: SnackBarBehavior.floating,
          ));
          widget.onUploaded();
        }
      } catch (_) {
        // เน็ตสะดุดชั่วคราว — รอบหน้าลองใหม่
      }
    });
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    if (_uploading) return;
    setState(() => _errorMsg = null);

    final XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: source,
        // Slips usually need to be readable, but 1600px on the longest
        // edge keeps file size under a few hundred KB and within the
        // 4 MB server cap. JPEG quality 80 ditto.
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
    } on Exception catch (e) {
      if (kDebugMode) debugPrint('[Wallet] picker error: $e');
      if (!mounted) return;
      setState(() => _errorMsg = 'เปิดกล้อง/แกลเลอรีไม่ได้ กรุณาลองใหม่');
      return;
    }
    if (picked == null) return; // user cancelled

    if (!mounted) return;
    setState(() => _uploading = true);
    try {
      final repo = await ref.read(walletRepositoryProvider.future);
      final res = await repo.uploadTopupSlip(
        transactionId: widget.txId,
        filePath: picked.path,
        fileName: picked.name,
      );
      // Surface success to the parent — it pops + refreshes.
      if (!mounted) return;

      // 🔴 ของเดิมทิ้งผลลัพธ์ทั้งก้อนแล้วโชว์ข้อความตายตัว 'รอแอดมินอนุมัติ'
      // ทั้งที่ SlipOK ตรวจผ่านแล้วเครดิตเข้าทันทีก็มี → ลูกค้าไม่กล้าเปิดไพ่ต่อ
      // และเคสที่ถูกปฏิเสธ ข้อความชี้ทางแก้ของเซิร์ฟเวอร์ก็หายไปด้วย
      final paid = res['paid'] == true;
      final msg = res['message']?.toString().trim();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg?.isNotEmpty == true
            ? msg!
            : 'ได้รับสลิปแล้วค่ะ ระบบกำลังตรวจสอบให้นะคะ'),
        backgroundColor: JuntraColors.bgPurpleDeep,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: paid ? 4 : 3),
      ));
      if (paid) {
        // เครดิตเข้าแล้ว — อัปเดตยอดในหัวแอพทันที ไม่ต้องรอผู้ใช้ลากรีเฟรช
        // ignore: unawaited_futures
        ref.read(authControllerProvider.notifier).refresh();
      }
      widget.onUploaded();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        // 409 มาได้สามความหมาย (tx_not_pending / duplicate_slip /
        // too_many_pending) แยกด้วย reason_code ไม่ใช่เหมาโดยรหัส HTTP
        // — เดิมลูกค้าที่แนบสลิปซ้ำเห็น 'รายการนี้ดำเนินการเสร็จแล้ว'
        // ซึ่งอ่านได้ว่าเงินเข้าแล้ว ทั้งที่ยัง pending อยู่ แล้วเดินจากไป
        _errorMsg = switch (e.reasonCode) {
          'duplicate_slip'  => 'สลิปใบนี้ถูกใช้ไปแล้วค่ะ กรุณาแนบสลิปของการโอนครั้งนี้',
          'tx_not_pending'  => 'รายการนี้ดำเนินการเสร็จแล้ว ไม่สามารถอัปโหลดสลิปใหม่ได้',
          _ => e.message,
        };
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _errorMsg = 'อัปโหลดไม่สำเร็จ — กรุณาลองใหม่';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
            Center(
              // ห้าม toInt() — SmsCheckerService ต่อท้ายสตางค์ 0.01–0.99 ให้ไม่ซ้ำ
              // เพื่อแมป SMS ธนาคารกับบิลใบเดียว ตัดเศษทิ้ง = ลูกค้าพิมพ์ยอดผิด
              // แล้วระบบจับคู่ไม่ได้ ต้องรอแอดมินตรวจมือ
              child: Text('เติมเครดิต ฿${widget.amount.toStringAsFixed(2)}',
                  style: baiJamjuree(size: 18, color: JuntraColors.gold)),
            ),
            const SizedBox(height: 16),
            _PromptPayInfoCard(
              id: widget.promptpayId,
              name: widget.promptpayName,
              amount: widget.amount,
              qrPayload: widget.qrPayload,
            ),
            const SizedBox(height: 14),
            if (widget.autoConfirm && _paid) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.check_circle, color: JuntraColors.mintGreen, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('เติมเครดิตสำเร็จแล้วค่ะ ✨',
                    style: baiJamjuree(size: 14, color: JuntraColors.mintGreen))),
              ]),
            ],
            if (widget.autoConfirm && !_paid) ...[
              const SizedBox(height: 10),
              const Row(children: [
                SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    valueColor: AlwaysStoppedAnimation<Color>(JuntraColors.gold),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(child: Text('กำลังรอเงินเข้า · แม่หมอจะเติมเครดิตให้ทันทีที่ระบบเห็นยอด',
                    style: TextStyle(fontSize: 11.5, color: JuntraColors.textMuted))),
              ]),
            ],
            if (widget.autoConfirm) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: JuntraColors.mintGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: JuntraColors.mintGreen.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.bolt, size: 16, color: JuntraColors.mintGreen),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'โอนตามจำนวนนี้เป๊ะ ๆ แล้วระบบจะเติมเครดิตให้อัตโนมัติทันทีที่เงินเข้า',
                        style: TextStyle(
                          fontSize: 12, color: JuntraColors.textCream, height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              (widget.instructions?.trim().isNotEmpty ?? false)
                  ? widget.instructions!.trim()
                  : '1. โอนเงินผ่านแอพธนาคารของคุณ "ตามจำนวนข้างต้นเป๊ะ ๆ"\n'
                      '2. กลับมาที่หน้านี้แล้วอัปโหลดสลิปด้านล่าง',
              style: const TextStyle(
                fontSize: 12, color: JuntraColors.textLavender, height: 1.6,
              ),
            ),
            const SizedBox(height: 16),
            if (_uploading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Column(
                  children: [
                    SizedBox(
                      width: 28, height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            JuntraColors.gold),
                      ),
                    ),
                    SizedBox(height: 10),
                    Text('กำลังอัปโหลดสลิป...',
                        style: TextStyle(
                          fontSize: 12, color: JuntraColors.textMuted,
                        )),
                  ],
                ),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: JuntraColors.gold,
                        foregroundColor: JuntraColors.bgPurpleDeep,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('ถ่ายรูปสลิป',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      onPressed: () => _pickAndUpload(ImageSource.camera),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            JuntraColors.purple.withValues(alpha: 0.3),
                        foregroundColor: JuntraColors.textCream,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('แกลเลอรี',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      onPressed: () => _pickAndUpload(ImageSource.gallery),
                    ),
                  ),
                ],
              ),
            ],
            if (_errorMsg != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.redAccent, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_errorMsg!,
                          style: const TextStyle(
                            fontSize: 12, color: JuntraColors.textCream,
                          )),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (widget.webFallbackUrl != null && widget.webFallbackUrl!.isNotEmpty)
              Center(
                child: TextButton(
                  onPressed: () async {
                    final uri = Uri.parse(widget.webFallbackUrl!);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    }
                  },
                  child: const Text('เปิดเว็บเพื่ออัปโหลดแทน →',
                      style: TextStyle(
                          color: JuntraColors.textFaint, fontSize: 11)),
                ),
              ),
            Center(
              child: TextButton(
                onPressed: _uploading ? null : () => Navigator.of(context).pop(),
                child: const Text('ปิด',
                    style: TextStyle(color: JuntraColors.textMuted)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromptPayInfoCard extends StatelessWidget {
  const _PromptPayInfoCard({
    required this.id, required this.name, required this.amount, this.qrPayload,
  });
  final String id;
  final String name;
  final double amount;
  /// Exact EMVCo payload from the backend (carries the unique payable amount).
  /// Preferred over a locally-built one so the QR matches the reserved amount.
  final String? qrPayload;

  @override
  Widget build(BuildContext context) {
    // Prefer the backend's exact payload (correct unique amount for SMS
    // auto-credit). Fall back to building one locally from id+amount only when
    // the backend didn't supply it and the receiver id is set + well-formed.
    final payload = (qrPayload != null && qrPayload!.trim().isNotEmpty)
        ? qrPayload!.trim()
        : (id.isEmpty ? null : PromptPayQr.build(proxyId: id, amount: amount));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: JuntraColors.mysticHeroGradient,
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('โอนผ่าน PromptPay',
              style: TextStyle(
                fontSize: 10, letterSpacing: 1.8,
                color: JuntraColors.textFaint, fontWeight: FontWeight.w600,
              )),
          if (payload != null) ...[
            const SizedBox(height: 12),
            Center(child: _QrBlock(payload: payload)),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
          _row('ผู้รับ', name.isEmpty ? '— กรุณาตั้งค่าใน /admin/wallet-settings —' : name),
          const SizedBox(height: 4),
          _row('PromptPay ID', id.isEmpty ? '— ยังไม่ได้ตั้งค่า —' : id, mono: true),
          const SizedBox(height: 4),
          _row('จำนวน', '฿${NumberFormat.decimalPattern('th').format(amount)}',
              highlight: true),
        ],
      ),
    );
  }

  Widget _row(String label, String value,
      {bool mono = false, bool highlight = false}) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(label, style: const TextStyle(
            fontSize: 11.5, color: JuntraColors.textMuted,
          )),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: TextStyle(
              fontSize: 13,
              color: highlight ? JuntraColors.gold : JuntraColors.textCream,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
              fontFamily: mono ? 'monospace' : null,
            ),
          ),
        ),
      ],
    );
  }
}

/// Scannable EMVCo PromptPay QR on the mandatory white quiet-zone. Banks'
/// scanners need dark modules on a light field, so this stays white even
/// inside the purple sheet.
class _QrBlock extends StatelessWidget {
  const _QrBlock({required this.payload});
  final String payload;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        boxShadow: const [
          BoxShadow(color: Color(0x55000000), blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('PromptPay',
              style: TextStyle(
                fontSize: 12, letterSpacing: 1.2,
                color: Color(0xFF002C6E), fontWeight: FontWeight.w800,
              )),
          const SizedBox(height: 8),
          QrImageView(
            data: payload,
            version: QrVersions.auto,
            size: 196,
            backgroundColor: Colors.white,
            // Medium EC tolerates a little print/screen noise while keeping
            // the module count low enough to scan from a phone screen.
            errorCorrectionLevel: QrErrorCorrectLevel.M,
          ),
          const SizedBox(height: 6),
          const Text('สแกนด้วยแอพธนาคารเพื่อโอน',
              style: TextStyle(fontSize: 11, color: Color(0xFF555555))),
        ],
      ),
    );
  }
}

class _PricingHint extends StatelessWidget {
  const _PricingHint({required this.pricing});
  final Map<String, dynamic> pricing;
  @override
  Widget build(BuildContext context) {
    // Show every feature the backend actually prices (keys present in the
    // /wallet pricing map), in a sensible order. Absent keys are skipped so we
    // never show a phantom "ฟรี" for a feature the backend didn't return.
    const defs = <(String, String, String)>[
      ('💬', 'สนทนากับแม่หมอ', 'chat_message'),
      ('🃏', 'ไพ่ใบเดียว',      'tarot_single'),
      ('🃏', 'เปิดไพ่ 3 ใบ',     'tarot_three'),
      ('❤️', 'ไพ่ความรัก',      'tarot_love'),
      ('💼', 'ไพ่การงาน-เงิน',   'tarot_career'),
      ('⚖️', 'ไพ่ทางแยก',       'tarot_decision'),
      ('🔮', 'Celtic Cross',     'tarot_celtic'),
      ('📅', 'ดวง 12 เดือน',     'tarot_year'),
      ('🔢', 'เลขศาสตร์',         'numerology'),
      ('✋', 'ดูลายมือ',          'palmistry'),
      ('☼', 'ฤกษ์ยาม',          'auspicious'),
    ];
    final items = <(String, String, num)>[
      for (final (icon, label, key) in defs)
        if (pricing.containsKey(key)) (icon, label, _num(pricing[key])),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        border: Border.all(color: JuntraColors.purple.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('อัตราค่าบริการ',
              style: TextStyle(
                fontSize: 11, letterSpacing: 1.6,
                color: JuntraColors.textFaint,
              )),
          const SizedBox(height: 8),
          for (final (icon, label, cost) in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Text(icon, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(label,
                      style: const TextStyle(
                        fontSize: 12.5, color: JuntraColors.textLavender,
                      ))),
                  Text(cost > 0 ? '฿${cost.toStringAsFixed(0)}' : 'ฟรี',
                      style: baiJamjuree(size: 13, color: JuntraColors.gold)),
                ],
              ),
            ),
        ],
      ),
    );
  }
  static num _num(dynamic v) => v is num ? v : 0;
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600,
          color: JuntraColors.textCream,
        ));
  }
}

class _TxTile extends StatelessWidget {
  const _TxTile({required this.tx, this.onReupload, this.onCancel});
  final Map<String, dynamic> tx;

  /// When set and this is a *pending top-up*, a "อัปโหลดสลิป" pill lets the
  /// user re-open the slip sheet — covers the case where they dismissed it
  /// before uploading.
  final VoidCallback? onReupload;

  /// When set and this is a *pending top-up*, a "ยกเลิก" pill cancels it.
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
    final isPositive = amount >= 0;
    final type = tx['type']?.toString() ?? '';
    final status = tx['status']?.toString() ?? 'success';
    final desc = tx['description']?.toString() ?? '';
    final created = tx['created_at']?.toString() ?? '';
    final canReupload =
        onReupload != null && type == 'topup' && status == 'pending';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        border: Border.all(color: JuntraColors.purple.withValues(alpha: 0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (isPositive
                          ? JuntraColors.mintGreen
                          : JuntraColors.purpleBright)
                      .withValues(alpha: 0.2),
                ),
                alignment: Alignment.center,
                child: Text(_typeIcon(type),
                    style: const TextStyle(fontSize: 16)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(desc.isEmpty ? _typeLabel(type) : desc,
                        style: const TextStyle(
                          fontSize: 12.5, color: JuntraColors.textCream,
                          fontWeight: FontWeight.w600,
                        )),
                    const SizedBox(height: 2),
                    Text('${_formatDate(created)} · ${_statusLabel(status)}',
                        style: const TextStyle(
                          fontSize: 10.5, color: JuntraColors.textFaint,
                        )),
                  ],
                ),
              ),
              Text(
                '${isPositive ? '+' : ''}฿${amount.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700,
                  color: isPositive
                      ? JuntraColors.mintGreen
                      : JuntraColors.purpleBright,
                ),
              ),
            ],
          ),
          if (canReupload) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onCancel != null) ...[
                  _TopupActionPill(
                    label: 'ยกเลิก',
                    icon: Icons.close_rounded,
                    color: const Color(0xFFFF8FA0),
                    onTap: onCancel!,
                  ),
                  const SizedBox(width: 8),
                ],
                _TopupActionPill(
                  label: 'อัปโหลดสลิป',
                  icon: Icons.upload_file_outlined,
                  color: JuntraColors.gold,
                  onTap: onReupload!,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _typeIcon(String t) => switch (t) {
        'topup' => '⬆',
        'debit' => '⬇',
        'refund' => '↩',
        _ => '•',
      };
  String _typeLabel(String t) => switch (t) {
        'topup' => 'เติมเงิน',
        'debit' => 'หักค่าบริการ',
        'refund' => 'คืนเครดิต',
        'adjustment' => 'ปรับยอด',
        _ => t,
      };
  String _statusLabel(String s) => switch (s) {
        'pending' => 'รอตรวจสอบ',
        'success' => 'สำเร็จ',
        'failed' => 'ปฏิเสธ',
        'refunded' => 'คืนเงินแล้ว',
      // ผู้ใช้สร้างสถานะนี้ได้เองจากปุ่มยกเลิกในหน้านี้ ถ้าไม่แปลจะขึ้นคำว่า
      // 'cancelled' กลางหน้าจอภาษาไทย ดูเหมือนระบบพังทั้งที่ทำงานถูก
      'cancelled' => 'ยกเลิกแล้ว',
        _ => s,
      };
  String _formatDate(String iso) {
    if (iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return DateFormat('d MMM HH:mm', 'th').format(dt.toLocal());
  }
}

/// Small outlined call-to-action pill shown on a pending top-up tile
/// (re-upload slip / cancel).
class _TopupActionPill extends StatelessWidget {
  const _TopupActionPill({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.w700,
                )),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const Icon(Icons.cloud_off, color: JuntraColors.textFaint, size: 36),
          const SizedBox(height: 10),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: JuntraColors.textMuted)),
          const SizedBox(height: 16),
          GhostButton(label: 'ลองอีกครั้ง', onPressed: onRetry),
        ],
      ),
    );
  }
}
