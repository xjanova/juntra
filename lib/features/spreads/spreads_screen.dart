import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../shared/data/fortune_categories.dart';
import '../../shared/data/spreads.dart';
import '../../shared/widgets/pill.dart';
import '../../shared/widgets/starry_background.dart';

/// Screen 3 — Spreads. Choose a tarot spread within a category.
class SpreadsScreen extends StatelessWidget {
  const SpreadsScreen({super.key, this.categoryId});
  final String? categoryId;

  @override
  Widget build(BuildContext context) {
    final cat = fortuneCategories.firstWhere(
      (c) => c.id == (categoryId ?? 'love'),
      orElse: () => fortuneCategories.first,
    );

    return Scaffold(
      body: Stack(
        children: [
          const StarryBackground(density: 40, intensity: 0.5),
          SafeArea(
            child: Column(
              children: [
                _Header(category: cat),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: spreads.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _SpreadTile(
                      spread: spreads[i],
                      onTap: () => context.go(
                        '${Routes.shuffle}?spread=${spreads[i].id}'
                        '&category=${cat.id}',
                      ),
                    ),
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
  const _Header({required this.category});
  final FortuneCategory category;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 16, 14),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: JuntraColors.gold, size: 28),
            onPressed: () => context.go(Routes.home),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ดวง${category.name}',
                  style: baiJamjuree(size: 19),
                ),
                const SizedBox(height: 2),
                Text(category.desc, style: const TextStyle(
                  fontSize: 11, color: JuntraColors.textMuted,
                )),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.favorite_border, color: JuntraColors.purpleBright),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, color: JuntraColors.purpleBright),
            onPressed: () => context.go(Routes.share),
          ),
        ],
      ),
    );
  }
}

class _SpreadTile extends StatelessWidget {
  const _SpreadTile({required this.spread, required this.onTap});
  final Spread spread;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(JuntraRadius.card),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: JuntraColors.purpleCardGradient,
          borderRadius: BorderRadius.circular(JuntraRadius.card),
          border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            _MiniDeck(count: spread.cards),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(spread.name, style: baiJamjuree(size: 17)),
                      const SizedBox(width: 8),
                      if (spread.popular)
                        const Pill(label: 'ยอดนิยม', color: Color(0xFFFF6B9D))
                      else if (spread.badge != null)
                        Pill(label: spread.badge!),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(spread.desc, style: const TextStyle(
                    fontSize: 12, color: JuntraColors.textLavender, height: 1.4,
                  )),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: spread.price == 0
                              ? JuntraColors.mintGreen.withValues(alpha: 0.18)
                              : JuntraColors.gold.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          spread.price == 0 ? 'ฟรี' : '฿${spread.price}',
                          style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700,
                            color: spread.price == 0
                                ? JuntraColors.mintGreen
                                : JuntraColors.gold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.arrow_forward_rounded,
                          color: JuntraColors.gold, size: 20),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniDeck extends StatelessWidget {
  const _MiniDeck({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) {
    final shown = count > 4 ? 4 : count;
    return SizedBox(
      width: 56, height: 80,
      child: Stack(
        children: List.generate(shown, (i) {
          return Positioned(
            left: i * 6.0, top: i * 4.0,
            child: Container(
              width: 38, height: 60,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2D1A5C), Color(0xFF1A0F2E)],
                ),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: JuntraColors.gold.withValues(alpha: 0.5), width: 0.8,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                i == shown - 1 ? '$count' : '☾',
                style: TextStyle(
                  fontSize: 11,
                  color: JuntraColors.goldLight,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
