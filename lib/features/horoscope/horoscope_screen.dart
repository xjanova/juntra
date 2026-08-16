import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/horoscope_repository.dart';
import '../../shared/data/juntra_art.dart';
import '../../shared/widgets/art_banner.dart';
import '../../shared/widgets/starry_background.dart';

/// ดวงรายวัน — pick a zodiac sign, read today's AI-generated horoscope from
/// GET /v1/horoscope/{slug}. Free + read-only.
class HoroscopeScreen extends ConsumerStatefulWidget {
  const HoroscopeScreen({super.key, this.initialSlug});
  final String? initialSlug;
  @override
  ConsumerState<HoroscopeScreen> createState() => _HoroscopeScreenState();
}

class _HoroscopeScreenState extends ConsumerState<HoroscopeScreen> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSlug;
  }

  @override
  Widget build(BuildContext context) {
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
                      icon: const Icon(Icons.chevron_left, color: JuntraColors.gold, size: 28),
                      onPressed: () {
                        if (_selected != null) {
                          setState(() => _selected = null);
                        } else {
                          context.canPop() ? context.pop() : context.go(Routes.home);
                        }
                      },
                    ),
                    Expanded(child: Text('ดวงรายวัน', style: baiJamjuree(size: 20))),
                    const SizedBox(width: 12),
                  ],
                ),
                Expanded(
                  child: _selected == null ? _grid() : _reading(_selected!),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid() {
    final signs = ref.watch(horoscopeSignsProvider);
    return signs.when(
      loading: () => const Center(child: CircularProgressIndicator(color: JuntraColors.gold)),
      error: (_, _) => _retry(() => ref.invalidate(horoscopeSignsProvider)),
      data: (list) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const ArtBanner(asset: JuntraArt.horoscope, height: 138),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.78,
            ),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final z = list[i];
              final slug = z['slug']?.toString() ?? '';
              return InkWell(
                onTap: () => setState(() => _selected = slug),
                borderRadius: BorderRadius.circular(JuntraRadius.card),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    gradient: JuntraColors.purpleCardGradient,
                    borderRadius: BorderRadius.circular(JuntraRadius.card),
                    border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.25)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // ภาพประจำราศีชุดเดียวกับเว็บ — เดิมทั้ง 12 ช่องเป็น
                      // สัญลักษณ์ตัวอักษรบนกล่องม่วง จึงดูเหมือนกันไปหมด
                      ZodiacBadge(
                        slug: slug,
                        glyph: z['glyph']?.toString() ?? '☾',
                        size: 54,
                      ),
                      const SizedBox(height: 6),
                      Text(z['name_th']?.toString() ?? '',
                          style: baiJamjuree(size: 13)),
                      const SizedBox(height: 2),
                      Text(z['date_range']?.toString() ?? '',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 9, color: JuntraColors.textFaint)),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _reading(String slug) {
    final async = ref.watch(dailyHoroscopeProvider(slug));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(color: JuntraColors.gold)),
      error: (_, _) => _retry(() => ref.invalidate(dailyHoroscopeProvider(slug))),
      data: (h) {
        final zodiac = (h['zodiac'] as Map?)?.cast<String, dynamic>() ?? const {};
        return RefreshIndicator(
          color: JuntraColors.gold,
          backgroundColor: JuntraColors.bgPurpleDeep,
          onRefresh: () async {
            ref.invalidate(dailyHoroscopeProvider(slug));
            await Future<void>.delayed(const Duration(milliseconds: 300));
          },
          child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            // วันที่ของดวงชุดนี้ — กันเคสเปิดแอพค้างข้ามเที่ยงคืนแล้วอ่านของเมื่อวาน
            if ((h['date']?.toString() ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'ดวงประจำวันที่ ${_thaiDate(h['date'].toString())}',
                  style: const TextStyle(
                    fontSize: 10, letterSpacing: 1.6,
                    color: JuntraColors.textFaint, fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            Row(
              children: [
                ZodiacBadge(
                  slug: zodiac['slug']?.toString() ?? slug,
                  glyph: zodiac['glyph']?.toString() ?? '☾',
                  size: 64,
                  selected: true,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ราศี${zodiac['name_th'] ?? ''}', style: baiJamjuree(size: 22)),
                      Text(
                        [
                          zodiac['date_range']?.toString(),
                          // ธาตุประจำราศี — ข้อมูลโหราศาสตร์พื้นฐานที่เว็บแสดง
                          // และ API ส่งมาให้อยู่แล้ว แต่แอพไม่เคยอ่าน
                          _elementTh(zodiac['element']?.toString()),
                        ].whereType<String>().where((t) => t.isNotEmpty).join(' · '),
                        style: const TextStyle(fontSize: 11, color: JuntraColors.textFaint),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: JuntraColors.mysticHeroGradient,
                borderRadius: BorderRadius.circular(JuntraRadius.hero),
                border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.4)),
              ),
              child: Text(h['summary']?.toString() ?? '',
                  style: const TextStyle(
                    fontSize: 14, color: JuntraColors.textLavender, height: 1.7,
                    fontStyle: FontStyle.italic,
                  )),
            ),
            const SizedBox(height: 14),
            _aspect('ความรัก', '♥', h['love']),
            _aspect('การงาน', '✦', h['career']),
            _aspect('การเงิน', '◈', h['money']),
            _aspect('สุขภาพ', '✚', h['health']),
            const SizedBox(height: 8),
            Row(
              children: [
                _lucky('เลขนำโชค', h['lucky_number']?.toString() ?? '—'),
                const SizedBox(width: 8),
                _lucky('สีมงคล', h['lucky_color']?.toString() ?? '—'),
                const SizedBox(width: 8),
                _lucky('ไพ่ประจำวัน', h['lucky_card']?.toString() ?? '—'),
              ],
            ),
          ],
          ),
        );
      },
    );
  }

  /// Fire/Earth/Air/Water → ไฟ/ดิน/ลม/น้ำ (ตรงกับ horoscope/show.blade.php)
  static String? _elementTh(String? en) => switch (en?.toLowerCase()) {
        'fire' => 'ธาตุไฟ',
        'earth' => 'ธาตุดิน',
        'air' => 'ธาตุลม',
        'water' => 'ธาตุน้ำ',
        _ => null,
      };

  /// 2026-08-16 → 16/08/2026 (รูปแบบเดียวกับ eyebrow ของเว็บ)
  static String _thaiDate(String iso) {
    final p = iso.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
  }

  Widget _aspect(String label, String icon, dynamic text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        border: Border.all(color: JuntraColors.purple.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(icon, style: const TextStyle(fontSize: 13, color: JuntraColors.gold)),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(
              fontSize: 11, letterSpacing: 1.5, color: JuntraColors.gold, fontWeight: FontWeight.w600,
            )),
          ]),
          const SizedBox(height: 4),
          Text(text?.toString() ?? '—', style: const TextStyle(
            fontSize: 13, color: JuntraColors.textLavender, height: 1.6,
          )),
        ],
      ),
    );
  }

  Widget _lucky(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: JuntraColors.bgDeepest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(JuntraRadius.card),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 9, color: JuntraColors.textFaint)),
            const SizedBox(height: 4),
            Text(value, textAlign: TextAlign.center,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: baiJamjuree(size: 15, color: JuntraColors.gold)),
          ],
        ),
      ),
    );
  }

  Widget _retry(VoidCallback onRetry) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, color: JuntraColors.textFaint, size: 40),
          const SizedBox(height: 10),
          const Text('โหลดดวงไม่สำเร็จ', style: TextStyle(color: JuntraColors.textMuted)),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('ลองใหม่',
              style: TextStyle(color: JuntraColors.gold))),
        ],
      ),
    );
  }
}
