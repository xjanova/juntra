import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../shared/widgets/gold_button.dart';
import '../../shared/widgets/starry_background.dart';

/// Screen 6 — Payment. Order summary, payment methods, promo input,
/// confirm CTA. Wires to /v1/payment/initiate which returns a method-
/// specific payload (PromptPay QR string, TrueMoney redirect URL, etc.)
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, required this.spreadId, required this.amount});
  final String spreadId;
  final int amount;
  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  String _method = 'promptpay';
  final _promo = TextEditingController();

  @override
  void dispose() {
    _promo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const StarryBackground(density: 30, intensity: 0.4),
          SafeArea(
            child: Column(
              children: [
                _Header(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      _OrderSummary(spreadId: widget.spreadId, amount: widget.amount),
                      const SizedBox(height: 16),
                      Text('วิธีชำระเงิน', style: baiJamjuree(size: 14)),
                      const SizedBox(height: 8),
                      _MethodTile(
                        id: 'promptpay', selected: _method == 'promptpay',
                        title: 'PromptPay', subtitle: 'สแกน QR · ทุกธนาคาร',
                        icon: '📱', onTap: (id) => setState(() => _method = id),
                      ),
                      _MethodTile(
                        id: 'truemoney', selected: _method == 'truemoney',
                        title: 'TrueMoney Wallet', subtitle: 'เปิดแอป TrueMoney',
                        icon: '🟠', onTap: (id) => setState(() => _method = id),
                      ),
                      _MethodTile(
                        id: 'card', selected: _method == 'card',
                        title: 'บัตรเครดิต/เดบิต', subtitle: 'Visa · Mastercard',
                        icon: '💳', onTap: (id) => setState(() => _method = id),
                      ),
                      _MethodTile(
                        id: 'wallet', selected: _method == 'wallet',
                        title: 'กระเป๋าจันทรา', subtitle: 'แต้มสะสม 480 pt',
                        icon: '✦', onTap: (id) => setState(() => _method = id),
                      ),
                      const SizedBox(height: 16),
                      _PromoInput(controller: _promo),
                      const SizedBox(height: 18),
                      if (_method == 'promptpay')
                        Center(child: _PromptPayQr(amount: widget.amount)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: GoldButton(
                    label: 'ยืนยันชำระ ฿${widget.amount}',
                    icon: const Icon(Icons.lock_outline),
                    size: GoldButtonSize.lg,
                    onPressed: () => context.pushReplacement(Routes.shuffle),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: JuntraColors.gold, size: 28),
            onPressed: () => context.pop(),
          ),
          Expanded(child: Text('ชำระเงิน', style: baiJamjuree(size: 19))),
        ],
      ),
    );
  }
}

class _OrderSummary extends StatelessWidget {
  const _OrderSummary({required this.spreadId, required this.amount});
  final String spreadId;
  final int amount;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: JuntraColors.purpleCardGradient,
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('สรุปคำสั่งซื้อ', style: TextStyle(
            fontSize: 10, letterSpacing: 2.4,
            color: JuntraColors.textFaint, fontWeight: FontWeight.w500,
          )),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Spread $spreadId', style: baiJamjuree(size: 16)),
              Text('฿$amount', style: baiJamjuree(size: 16, color: JuntraColors.gold)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.id, required this.selected,
    required this.title, required this.subtitle,
    required this.icon, required this.onTap,
  });
  final String id;
  final bool selected;
  final String title;
  final String subtitle;
  final String icon;
  final ValueChanged<String> onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onTap(id),
      borderRadius: BorderRadius.circular(JuntraRadius.card),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(JuntraRadius.card),
          border: Border.all(color: selected
              ? JuntraColors.gold
              : JuntraColors.purple.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600,
                    color: JuntraColors.textCream,
                  )),
                  Text(subtitle, style: const TextStyle(
                    fontSize: 11, color: JuntraColors.textMuted,
                  )),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: selected ? JuntraColors.gold : JuntraColors.textFaint,
            ),
          ],
        ),
      ),
    );
  }
}

class _PromoInput extends StatelessWidget {
  const _PromoInput({required this.controller});
  final TextEditingController controller;
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: JuntraColors.textCream, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'มีรหัสส่วนลด?',
        hintStyle: const TextStyle(color: JuntraColors.textFaint),
        prefixIcon: const Icon(Icons.local_offer_outlined,
            color: JuntraColors.gold, size: 18),
        filled: true,
        fillColor: JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _PromptPayQr extends StatelessWidget {
  const _PromptPayQr({required this.amount});
  final int amount;
  @override
  Widget build(BuildContext context) {
    // In production, /v1/payment/initiate returns the EMV QR string.
    // For now, we display a placeholder containing the amount.
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(JuntraRadius.card),
      ),
      child: Column(
        children: [
          QrImageView(
            data: 'PROMPTPAY|JUNTRA|$amount',
            version: QrVersions.auto, size: 180,
          ),
          const SizedBox(height: 8),
          Text('สแกน QR เพื่อชำระ ฿$amount',
              style: const TextStyle(
                color: JuntraColors.bgPurpleDeep,
                fontWeight: FontWeight.w600,
              )),
        ],
      ),
    );
  }
}
