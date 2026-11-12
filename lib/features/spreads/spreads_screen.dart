import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/art_banner.dart';
import '../../shared/data/juntra_art.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/rooms_repository.dart';
import '../../core/api/tarot_packages_repository.dart';
import '../../shared/data/fortune_categories.dart';
import '../../shared/widgets/pill.dart';
import '../../shared/widgets/starry_background.dart';
import '../../shared/widgets/tarot_card_widgets.dart';
import '../../shared/format/credits.dart';
import 'package_groups.dart';

/// Screen 3 — แพ็กเกจไพ่ (ชุดเดียวกับเมนูไพ่ในห้องผู้พยากรณ์บนเว็บ) — เลือกแล้วเข้าซีนสับไพ่
///
/// รายการ ราคา ภาพประกอบ ข้อห้ามเปิดซ้ำ และผู้อ่านของแต่ละแพ็กเกจ มาจากเซิร์ฟเวอร์ทั้งหมด
/// (`GET /v1/tarot/packages`) — หลังบ้านเปิด/ปิด/ปรับราคาแล้วแอพเห็นทันทีโดยไม่ต้องออกรุ่นใหม่
/// เซิร์ฟเวอร์บอกห้องมาด้วย (2026-11) → จัดกลุ่ม "อ่านโดย น้องบุษบา / แม่หมอ" ตามลำดับห้องของเว็บ
class SpreadsScreen extends ConsumerWidget {
  const SpreadsScreen({super.key, this.categoryId});
  final String? categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ไม่ได้มาจากการ์ดหมวด (เช่นแตะไพ่ประจำวันบนหน้าแรก) = ดวงภาพรวม
    // เดิมตกไปเป็น 'love' หัวจอจึงขึ้น "ดวงความรัก" ทั้งที่ไม่ได้เลือก
    final cat = fortuneCategories.firstWhere(
      (c) => c.id == (categoryId ?? 'general'),
      orElse: () => fortuneCategories.first,
    );
    final async = ref.watch(tarotPackagesProvider);
    final rooms = ref.watch(roomsValueProvider);

    void open(TarotPackage p) =>
        context.push('${Routes.shuffle}?spread=${p.key}&category=${cat.id}');

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
                      // ครั้งแรกเท่านั้น — ดึงลงรีเฟรชใช้วงหมุนของ RefreshIndicator ไม่ล้างรายการเดิม
                      loading: () => const Center(
                        child: CircularProgressIndicator(color: JuntraColors.gold),
                      ),
                      // ไม่เกิดจริง (repository คืนสำรองในเครื่องเสมอ) แต่กันไว้
                      error: (_, _) => ListView(children: const [SizedBox(height: 80)]),
                      data: (packages) {
                        final items = <Widget>[
                          // ภาพประจำหมวดชุดเดียวกับการ์ดบนหน้าแรก — เห็นว่ากำลังดูเรื่องอะไร
                          ArtBanner(
                            asset: JuntraArt.category(cat.id),
                            height: 132,
                            alignment: const Alignment(0, -0.42),
                            overlay: Text(
                              'เลือกแพ็กเกจไพ่สำหรับดวง${cat.name}',
                              style: baiJamjuree(size: 15, color: JuntraColors.goldLight),
                            ),
                          ),
                        ];
                        if (hasReaderInfo(packages)) {
                          for (final g in groupByReader(packages, rooms)) {
                            items.add(_ReaderHeader(group: g));
                            for (final p in g.packages) {
                              items.add(_PackageTile(package: p, accent: g.accent, onTap: () => open(p)));
                            }
                          }
                        } else {
                          // เซิร์ฟเวอร์เก่า (ไม่บอกห้อง) — รายการเดียวแบบเดิม
                          for (final p in packages.where((p) => !p.webOnly)) {
                            items.add(_PackageTile(package: p, onTap: () => open(p)));
                          }
                        }
                        if (items.length == 1) items.add(const _EmptyPackages());
                        return ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (_, i) => items[i],
                        );
                      },
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
          // เว้นที่ให้โลโก้มุมขวาบน (StarryBackground)
          const SizedBox(width: StarryBackground.logoReserve),
        ],
      ),
    );
  }
}

/// หัวกลุ่ม "อ่านโดย …" — รูปผู้พยากรณ์ + สีประจำห้อง (ชุดเดียวกับหน้าเลือกห้องของเว็บ)
class _ReaderHeader extends StatelessWidget {
  const _ReaderHeader({required this.group});
  final ReaderGroup group;

  @override
  Widget build(BuildContext context) {
    final accent = group.accent;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Container(
            width: 38, height: 38,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: accent.withValues(alpha: 0.8), width: 1.4),
              boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 12)],
            ),
            child: Image.asset(
              JuntraArt.room(group.roomKey),
              fit: BoxFit.cover,
              alignment: const Alignment(0, -0.6),
              errorBuilder: (_, _, _) => Image.asset(
                OracleRoom.fallbackImage,
                fit: BoxFit.cover,
                alignment: const Alignment(0, -0.6),
                errorBuilder: (_, _, _) => ColoredBox(color: accent.withValues(alpha: 0.25)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text('อ่านโดย ', style: TextStyle(fontSize: 12.5, color: accent.withValues(alpha: 0.85))),
          Flexible(
            child: Text(
              group.readerName,
              overflow: TextOverflow.ellipsis,
              style: baiJamjuree(size: 16, color: accent),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [accent.withValues(alpha: 0.5), accent.withValues(alpha: 0)]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PackageTile extends StatelessWidget {
  const _PackageTile({required this.package, required this.onTap, this.accent});
  final TarotPackage package;
  final VoidCallback onTap;

  /// สีของผู้อ่าน (มีเมื่อจัดกลุ่ม) — ขอบการ์ดเรืองตามห้อง
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final p = package;
    final price = p.price;
    final edge = accent ?? JuntraColors.gold;
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
          border: Border.all(color: edge.withValues(alpha: accent == null ? 0.25 : 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 7,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _PackageArt(package: p),
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
                      Icon(Icons.arrow_forward_rounded, color: edge, size: 20),
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

/// ภาพประจำแพ็กเกจ: ภาพจากเซิร์ฟเวอร์ → ภาพในแอพ (assets/images/spreads/{key}.webp) → กองไพ่จิ๋ว
class _PackageArt extends StatelessWidget {
  const _PackageArt({required this.package});
  final TarotPackage package;

  @override
  Widget build(BuildContext context) {
    final local = Image.asset(
      JuntraArt.spread(package.key),
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _ArtFallback(count: package.cards),
    );
    final url = package.imageUrl;
    if (url == null) return local;
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, _) => const _ImageFallback(),
      errorWidget: (_, _, _) => local,
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

/// ไม่มีภาพเลย (ออฟไลน์ + ยังไม่มีไฟล์ในแอพ) — พื้นม่วง + กองไพ่จิ๋วตรงกลาง
class _ArtFallback extends StatelessWidget {
  const _ArtFallback({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const _ImageFallback(),
        Center(child: _MiniDeck(count: count)),
      ],
    );
  }
}

/// ไม่มีแพ็กเกจที่ขายในแอพตอนนี้ (หลังบ้านปิดหมด/เหลือแต่แพ็กเกจที่ขายในห้องแชทเว็บ)
class _EmptyPackages extends StatelessWidget {
  const _EmptyPackages();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        children: [
          Icon(Icons.style_outlined, color: JuntraColors.textFaint, size: 40),
          SizedBox(height: 10),
          Text(
            'ตอนนี้ยังไม่มีแพ็กเกจไพ่เปิดขาย ลองดึงหน้าจอลงเพื่อโหลดใหม่อีกครั้งนะคะ',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: JuntraColors.textMuted, height: 1.6),
          ),
        ],
      ),
    );
  }
}

/// กองไพ่จิ๋ว — แสดงแทนภาพแพ็กเกจตอนออฟไลน์/ยังไม่มีภาพ ใช้หลังไพ่ลายเดียวกับพัดไพ่
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
            child: Stack(
              alignment: Alignment.center,
              children: [
                const CardBack(width: 38, height: 60),
                if (i == shown - 1)
                  Container(
                    width: 22, height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.85),
                      border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.7), width: 0.8),
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        fontSize: 11,
                        color: JuntraColors.goldLight,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
