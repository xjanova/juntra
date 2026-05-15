import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/wallet_repository.dart';
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
    setState(() => _overview = _load());
    await _overview;
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
                          _TopupRow(onPick: (amount) => _startTopup(amount)),
                          const SizedBox(height: 18),
                          _PricingHint(pricing: pricing.cast<String, dynamic>()),
                          const SizedBox(height: 18),
                          if (txs.isNotEmpty) ...[
                            _SectionLabel('รายการล่าสุด'),
                            const SizedBox(height: 8),
                            for (final t in txs) _TxTile(tx: t.cast<String, dynamic>()),
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
    final Map<String, dynamic> initiated;
    try {
      final repo = await ref.read(walletRepositoryProvider.future);
      initiated = await repo.startPromptPayTopup(amount: amount);
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
      return;
    }
    if (!mounted) return;
    final txMap = (initiated['transaction'] as Map?)?.cast<String, dynamic>()
        ?? const {};
    final txId = (txMap['id'] as num?)?.toInt();
    if (txId == null) {
      _toast('สร้างรายการไม่สำเร็จ — ไม่ได้รับเลขที่รายการ');
      return;
    }
    await _openTopupSheet(
      txId: txId,
      amount: amount,
      promptpay: (initiated['promptpay'] as Map?)?.cast<String, dynamic>()
          ?? const {},
      slipUploadUrl: initiated['slip_upload_url']?.toString(),
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
        onUploaded: () {
          if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
        },
      ),
    );
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
  const _TopupRow({required this.onPick});
  final ValueChanged<double> onPick;
  static const _options = <double>[100, 200, 500, 1000];

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
        Row(
          children: [
            for (final amt in _options) ...[
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(JuntraRadius.card),
                  onTap: () => onPick(amt),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
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
            ],
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'โอนตามจำนวน แล้วถ่ายรูปสลิปอัปโหลดในแอพได้เลย · แอดมินอนุมัติภายในไม่กี่นาที',
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
  });
  final int txId;
  final double amount;
  final String promptpayId;
  final String promptpayName;
  final String? webFallbackUrl;
  final VoidCallback onUploaded;

  @override
  ConsumerState<_TopupSheet> createState() => _TopupSheetState();
}

class _TopupSheetState extends ConsumerState<_TopupSheet> {
  final _picker = ImagePicker();
  bool _uploading = false;
  String? _errorMsg;

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
      if (!mounted) return;
      setState(() => _errorMsg = 'เปิดกล้อง/แกลเลอรีไม่ได้: ${e.toString()}');
      return;
    }
    if (picked == null) return; // user cancelled

    if (!mounted) return;
    setState(() => _uploading = true);
    try {
      final repo = await ref.read(walletRepositoryProvider.future);
      await repo.uploadTopupSlip(
        transactionId: widget.txId,
        filePath: picked.path,
        fileName: picked.name,
      );
      // Surface success to the parent — it pops + refreshes.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('อัปโหลดสลิปสำเร็จ · แอดมินจะตรวจสอบและอนุมัติเร็วๆ นี้'),
        backgroundColor: JuntraColors.bgPurpleDeep,
        behavior: SnackBarBehavior.floating,
      ));
      widget.onUploaded();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _errorMsg = e.statusCode == 409
            ? 'รายการนี้ดำเนินการเสร็จแล้ว ไม่สามารถอัปโหลดสลิปใหม่ได้'
            : e.message;
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
              child: Text('เติมเครดิต ฿${widget.amount.toInt()}',
                  style: baiJamjuree(size: 18, color: JuntraColors.gold)),
            ),
            const SizedBox(height: 16),
            _PromptPayInfoCard(
              id: widget.promptpayId,
              name: widget.promptpayName,
              amount: widget.amount,
            ),
            const SizedBox(height: 14),
            const Text(
              '1. โอนเงินผ่านแอพธนาคารของคุณตามจำนวนข้างต้น\n'
              '2. กลับมาที่หน้านี้แล้วอัปโหลดสลิปด้านล่าง',
              style: TextStyle(
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
    required this.id, required this.name, required this.amount,
  });
  final String id;
  final String name;
  final double amount;

  @override
  Widget build(BuildContext context) {
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

class _PricingHint extends StatelessWidget {
  const _PricingHint({required this.pricing});
  final Map<String, dynamic> pricing;
  @override
  Widget build(BuildContext context) {
    final items = <(String, String, num)>[
      ('💬', 'สนทนากับแม่หมอ', _num(pricing['chat_message'])),
      ('🃏', 'เปิดไพ่ 3 ใบ',     _num(pricing['tarot_three'])),
      ('🔮', 'Celtic Cross',     _num(pricing['tarot_celtic'])),
      ('🔢', 'เลขศาสตร์',         _num(pricing['numerology'])),
      ('✋', 'ดูลายมือ',          _num(pricing['palmistry'])),
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
  const _TxTile({required this.tx});
  final Map<String, dynamic> tx;
  @override
  Widget build(BuildContext context) {
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
    final isPositive = amount >= 0;
    final type = tx['type']?.toString() ?? '';
    final status = tx['status']?.toString() ?? 'success';
    final desc = tx['description']?.toString() ?? '';
    final created = tx['created_at']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        border: Border.all(color: JuntraColors.purple.withValues(alpha: 0.2)),
      ),
      child: Row(
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
            (isPositive ? '+' : '') + '฿${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w700,
              color: isPositive ? JuntraColors.mintGreen : JuntraColors.purpleBright,
            ),
          ),
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
        _ => s,
      };
  String _formatDate(String iso) {
    if (iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return DateFormat('d MMM HH:mm', 'th').format(dt.toLocal());
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
