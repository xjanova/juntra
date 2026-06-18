import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/wallet_repository.dart';
import 'starry_background.dart';

/// Shared input decoration for the non-tarot fortune forms.
InputDecoration fortuneInputDecoration(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: JuntraColors.textFaint, fontSize: 13),
      filled: true,
      fillColor: JuntraColors.bgPurpleDeep.withValues(alpha: 0.6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: JuntraColors.purple.withValues(alpha: 0.4)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: JuntraColors.purple.withValues(alpha: 0.4)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: JuntraColors.gold, width: 1.5),
      ),
    );

/// A labelled field group.
class FortuneField extends StatelessWidget {
  const FortuneField({super.key, required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(
          fontSize: 12, color: JuntraColors.textFaint, letterSpacing: 0.5,
        )),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

/// Common chrome for the numerology / auspicious / palmistry input screens —
/// starry background, back header with a live price badge (from /v1/wallet),
/// subtitle, the form body, and an error banner.
class FortuneFormScaffold extends ConsumerWidget {
  const FortuneFormScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.error,
    this.busy = false,
    this.featureKey,
  });
  final String title;
  final String subtitle;
  final List<Widget> children;
  final String? error;
  final bool busy;
  /// Pricing key (e.g. 'numerology') → shows a live ฿ badge.
  final String? featureKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    int? price;
    if (featureKey != null) {
      final pricing = ref.watch(walletPricingProvider).valueOrNull ?? const {};
      final p = pricing[featureKey];
      if (p != null) price = p.round();
    }

    return Scaffold(
      body: Stack(
        children: [
          const StarryBackground(density: 40, intensity: 0.5),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, color: JuntraColors.gold, size: 28),
                      onPressed: () => context.canPop() ? context.pop() : context.go(Routes.home),
                    ),
                    Expanded(child: Text(title, style: baiJamjuree(size: 20))),
                    if (price != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: JuntraColors.gold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(price == 0 ? 'ฟรี' : '฿$price',
                            style: const TextStyle(
                              fontSize: 12, color: JuntraColors.gold, fontWeight: FontWeight.w700,
                            )),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(subtitle, style: const TextStyle(
                    fontSize: 13, color: JuntraColors.textMuted, height: 1.5,
                  )),
                ),
                const SizedBox(height: 24),
                ...children,
                if (error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0x33FF6B47),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0x66FF6B47)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, size: 18, color: Color(0xFFFFB59A)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(error!, style: const TextStyle(
                          fontSize: 12.5, color: Color(0xFFFFD9C5), height: 1.4,
                        ))),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
