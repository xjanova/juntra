import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
/// Top-up flow: select amount → POST /wallet/topup/promptpay → backend
/// returns the PromptPay receiving info + a `slip_upload_url` pointing
/// to juntraweb's web `/wallet/topup/{tx}` page where the user uploads
/// the slip image. We open that URL in the system browser (or in-app
/// webview later) — same upload flow shared with the desktop site.
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
    try {
      final repo = await ref.read(walletRepositoryProvider.future);
      final res = await repo.startPromptPayTopup(amount: amount);
      final url = res['slip_upload_url']?.toString();
      if (!mounted) return;
      if (url == null || url.isEmpty) {
        _toast('สร้างรายการไม่สำเร็จ');
        return;
      }
      final ok = await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication);
      if (!ok) {
        _toast('เปิดหน้าเติมเงินไม่สำเร็จ — ลองอีกครั้ง');
      } else {
        _toast('โอนเงินตามจำนวน แล้วอัปโหลดสลิปในหน้าที่เปิดใหม่ค่ะ');
        // Refresh after the user is likely back from the browser.
        Future<void>.delayed(const Duration(seconds: 6), _refresh);
      }
    } on ApiException catch (e) {
      _toast(e.message);
    }
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
          'ระบบจะเปิดหน้าอัปโหลดสลิปในเว็บเบราว์เซอร์ · แอดมินอนุมัติภายในไม่กี่นาที',
          style: TextStyle(fontSize: 11, color: JuntraColors.textFaint, height: 1.5),
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
