import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/horoscope_repository.dart';
import '../../shared/data/juntra_art.dart';
import '../../shared/widgets/art_banner.dart';
import '../../shared/widgets/starry_background.dart';

/// ปีนักษัตร — 12 นักษัตรไทย พร้อมนิสัยประจำปีเกิด
///
/// เว็บมีหน้านี้มานานแล้ว (`/horoscope/thai-zodiac`) แต่แอพเข้าถึงไม่ได้เลย
/// เพราะไม่เคยมี endpoint — ผู้ใช้แอพจึงเห็นเนื้อหาน้อยกว่าคนที่เปิดเว็บ
///
/// ปีนักษัตรของปีปัจจุบันมาจาก **เซิร์ฟเวอร์** ไม่ใช่คำนวณในแอพ
/// (กฎเหล็กข้อ 1: ค่าที่อ้างเป็นผลคำนวณต้องมีแหล่งเดียว)
class ThaiZodiacScreen extends ConsumerWidget {
  const ThaiZodiacScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(thaiZodiacProvider);

    return Scaffold(
      body: Stack(
        children: [
          const StarryBackground(density: 40, intensity: 0.5),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left,
                          color: JuntraColors.gold, size: 28),
                      onPressed: () => context.canPop()
                          ? context.pop()
                          : context.go(Routes.home),
                    ),
                    Expanded(child: Text('ปีนักษัตร', style: baiJamjuree(size: 20))),
                    const SizedBox(width: 12),
                  ],
                ),
                Expanded(
                  child: async.when(
                    loading: () => const Center(
                      child: CircularProgressIndicator(color: JuntraColors.gold),
                    ),
                    error: (_, _) => Center(
                      child: TextButton(
                        onPressed: () => ref.invalidate(thaiZodiacProvider),
                        child: const Text('โหลดไม่สำเร็จ · แตะเพื่อลองใหม่',
                            style: TextStyle(color: JuntraColors.gold)),
                      ),
                    ),
                    data: (data) => _list(context, data),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, ThaiZodiacInfo data) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const ArtBanner(asset: JuntraArt.thaiZodiac, height: 132),
        const SizedBox(height: 8),
        if (data.currentSlug != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'ปี ${data.year} เป็นปี'
              '${data.signs.firstWhere(
                    (s) => s['slug'] == data.currentSlug,
                    orElse: () => const {},
                  )['name_th'] ?? ''}',
              style: baiJamjuree(size: 15, color: JuntraColors.gold),
            ),
          ),
        for (final z in data.signs)
          _SignTile(sign: z, current: z['slug'] == data.currentSlug),
      ],
    );
  }
}

class _SignTile extends StatelessWidget {
  const _SignTile({required this.sign, required this.current});
  final Map<String, dynamic> sign;
  final bool current;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: current
            ? JuntraColors.mysticHeroGradient
            : JuntraColors.purpleCardGradient,
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        border: Border.all(
          color: JuntraColors.gold.withValues(alpha: current ? 0.6 : 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44, height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.7),
              border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.35)),
            ),
            child: Text(sign['glyph']?.toString() ?? '·',
                style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('ปี${sign['name_th'] ?? ''}', style: baiJamjuree(size: 15)),
                    if (current) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: JuntraColors.gold.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('ปีนี้', style: TextStyle(
                          fontSize: 9.5, color: JuntraColors.gold,
                          fontWeight: FontWeight.w700,
                        )),
                      ),
                    ],
                  ],
                ),
                if ((sign['traits_th']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(sign['traits_th'].toString(), style: const TextStyle(
                    fontSize: 12.5, color: JuntraColors.textLavender, height: 1.6,
                  )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
