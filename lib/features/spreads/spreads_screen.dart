import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/art_banner.dart';
import '../../shared/data/juntra_art.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/tarot_packages_repository.dart';
import '../../shared/data/fortune_categories.dart';
import '../../shared/widgets/pill.dart';
import '../../shared/widgets/starry_background.dart';
import '../../shared/format/credits.dart';

/// Screen 3 — แพ็กเกจไพ่ (ชุดเดียวกับหน้า /tarot บนเว็บ) — เลือกแล้วเข้าซีนสับไพ่
///
/// รายการ ราคา ภาพประกอบ ข้อห้ามเปิดซ้ำ และแพ็กเกจใหม่ (คุณไสย) มาจากเซิร์ฟเวอร์ทั้งหมด
/// (`GET /v1/tarot/packages`) — หลังบ้านเปิด/ปิด/ปรับราคาแล้วแอพเห็นทันทีโดยไม่ต้องออกรุ่นใหม่
class SpreadsScreen extends ConsumerWidget {
  const SpreadsScreen({super.key, this.categoryId});
  final String? categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cat = fortuneCategories.firstWhere(
      (c) => c.id == (categoryId ?? 'love'),
      orElse: () => fortuneCategories.first,
    );
    final async = ref.watch(tarotPackagesProvider);

    return Scaffold(
      body: Stack(
        children: [
          const StarryBackground(density: 40, intensity: 0.5),
          SafeArea(
            child: Column(
              children: [
                _Header(category: cat),
                Expanded(
                  child: RefreshIndicator(
                    color: JuntraColors.gold,
                    backgroundColor: JuntraColors.bgPurpleDeep,
                    onRefresh: () => ref.refresh(tarotPackagesProvider.future),
                    child: async.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(color: JuntraColors.gold),
                      ),
                      // ไม่เกิดจริง (repository คืนสำรองในเครื่องเสมอ) แต่กันไว้
                      error: (_, _) => ListView(children: const [SizedBox(height: 80)]),
                      data: (packages) => ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: packages.length + 1,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (_, i) {
                          if (i == 0) {
                            return const ArtBanner(asset: JuntraArt.tarot, height: 118);
                          }
                          final p = packages[i - 1];
                          return _PackageTile(
                            package: p,
                            onTap: () => context.push(
                              '${Routes.shuffle}?spread=${p.key}&category=${cat.id}',
                            ),
                          );
                        },
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
            onPressed: () => context.canPop() ? context.pop() : context.go(Routes.home),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ดวง${category.name}', style: baiJamjuree(size: 19)),
                const SizedBox(height: 2),
                Text(category.desc, style: const TextStyle(
                  fontSize: 11, color: JuntraColors.textMuted,
                )),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, color: JuntraColors.purpleBright),
            onPressed: () => context.push(Routes.share),
          ),
        ],
      ),
    );
  }
}

class _PackageTile extends StatelessWidget {
  const _PackageTile({required this.package, required this.onTap});
  final TarotPackage package;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = package;
    final price = p.price;
    final notes = <String>[
      if (p.est != null && p.est!.isNotEmpty) 'ใช้เวลา ~${p.est}',
      if (p.birth) 'ผสานดวงวันเกิด',
      if (p.cooldownDays > 0) 'เปิดซ้ำได้ทุก ${p.cooldownDays} วัน',
    ];
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(JuntraRadius.card),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: JuntraColors.purpleCardGradient,
          borderRadius: BorderRadius.circular(JuntraRadius.card),
          border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (p.imageUrl != null)
              AspectRatio(
                aspectRatio: 16 / 7,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: p.imageUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const _ImageFallback(),
                      placeholder: (_, _) => const _ImageFallback(),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                          colors: [Color(0x00000000), Color(0xCC0A0414)],
                        ),
                      ),
                    ),
                    if (p.eyebrow != null)
                      Positioned(left: 12, bottom: 10, child: Pill(label: p.eyebrow!)),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (p.imageUrl == null) ...[
                    _MiniDeck(count: p.cards),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.nameTh, style: baiJamjuree(size: 17)),
                        if (p.tagline != null && p.tagline!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(p.tagline!, style: const TextStyle(
                            fontSize: 12, color: JuntraColors.textLavender, height: 1.45,
                          )),
                        ],
                        if (notes.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(notes.join(' · '), style: const TextStyle(
                            fontSize: 11, color: JuntraColors.textMuted,
                          )),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            if (price != null) _PriceBadge(price: price, free: p.free),
                            const Spacer(),
                            Text('${p.cards} ใบ', style: const TextStyle(fontSize: 12, color: JuntraColors.textMuted)),
                            const SizedBox(width: 6),
                            const Icon(Icons.arrow_forward_rounded, color: JuntraColors.gold, size: 20),
                          ],
                        ),
                      ],
                    ),
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

class _PriceBadge extends StatelessWidget {
  const _PriceBadge({required this.price, required this.free});
  final num price;
  final bool free;
  @override
  Widget build(BuildContext context) {
    final isFree = free || price <= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (isFree ? JuntraColors.mintGreen : JuntraColors.gold).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isFree ? 'ฟรี' : formatCredits(price),
        style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700,
          color: isFree ? JuntraColors.mintGreen : JuntraColors.gold,
        ),
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();
  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF2D1A5C), Color(0xFF1A0F2E)]),
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
                style: const TextStyle(
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
