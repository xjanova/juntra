import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../shared/data/fortune_categories.dart';
import '../../shared/data/tarot_deck.dart';
import '../../shared/widgets/pill.dart';
import '../../shared/widgets/starry_background.dart';
import '../../shared/widgets/tarot_card_widgets.dart';
import '../../shared/widgets/xman_studio_footer.dart';

/// Screen 2 — Home. Daily card hero, daily transit reading, quick stats,
/// fortune categories grid (2×4), Mae Mor online card, recent readings.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final card = tarotDeck[18]; // The Moon — daily default
    // Defensive: even with locale data initialized in main(), fall back
    // to a hand-rolled Thai weekday array if anything goes sideways here
    // — never let a single date format throw and black-out the screen.
    String weekday;
    try {
      weekday = DateFormat('EEEE', 'th').format(DateTime.now());
    } catch (_) {
      const days = ['จันทร์', 'อังคาร', 'พุธ', 'พฤหัสบดี',
                    'ศุกร์', 'เสาร์', 'อาทิตย์'];
      weekday = days[(DateTime.now().weekday - 1) % 7];
    }

    return Scaffold(
      body: Stack(
        children: [
          const StarryBackground(density: 50, intensity: 0.6),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                _Greeting(weekday: weekday),
                const SizedBox(height: 16),
                _DailyCardHero(card: card),
                const SizedBox(height: 14),
                _DailyTransitCard(),
                const SizedBox(height: 14),
                _QuickStatsRow(),
                const SizedBox(height: 18),
                _SectionLabel('หมวดดูดวง'),
                const SizedBox(height: 10),
                _CategoriesGrid(),
                const SizedBox(height: 18),
                _MaeMorOnlineCard(),
                const SizedBox(height: 18),
                _SectionLabel('ดูดวงล่าสุดของลูก'),
                const SizedBox(height: 10),
                _RecentReadingTile(
                  category: 'love', date: '2 พ.ค.', time: '14:32',
                  preview: 'ทาโรต์ 3 ใบ ความรักของลูกกำลังก้าวจากเงาสู่แสง...',
                ),
                const SizedBox(height: 8),
                _RecentReadingTile(
                  category: 'work', date: '28 เม.ย.', time: '21:08',
                  preview: 'ดวงการงาน เดือนนี้มีโอกาสใหม่เข้ามา ควรรีบคว้าไว้...',
                ),
                const SizedBox(height: 24),
                const Center(child: XmanStudioFooter()),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const _JuntraTabBar(currentIndex: 0),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.weekday});
  final String weekday;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'สวัสดี · $weekday',
                style: const TextStyle(
                  fontSize: 9, letterSpacing: 2.4,
                  color: JuntraColors.textFaint, fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text('คุณมาลี ✨', style: baiJamjuree(size: 22)),
            ],
          ),
        ),
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [JuntraColors.bgPurpleLight, JuntraColors.bgPurple],
            ),
            border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.5)),
          ),
          alignment: Alignment.center,
          child: const Text('ม', style: TextStyle(
            color: JuntraColors.goldLight,
            fontWeight: FontWeight.w700,
          )),
        ),
      ],
    );
  }
}

class _DailyCardHero extends StatelessWidget {
  const _DailyCardHero({required this.card});
  final TarotCard card;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: JuntraColors.purpleCardGradient,
        borderRadius: BorderRadius.circular(JuntraRadius.hero),
        border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.3)),
        boxShadow: const [
          BoxShadow(color: Color(0x99000000), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: Row(
        children: [
          CardFront(card: card, width: 88, height: 145),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Pill(label: 'ไพ่ประจำวัน', icon: Icon(Icons.auto_awesome)),
                const SizedBox(height: 8),
                Text(card.thai, style: baiJamjuree(size: 19)),
                const SizedBox(height: 2),
                Text(
                  card.name,
                  style: const TextStyle(
                    fontSize: 11,
                    color: JuntraColors.textFaint,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  card.meaning,
                  maxLines: 3, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12, color: JuntraColors.textLavender, height: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text('อ่านเต็ม →', style: TextStyle(
                  fontSize: 12, color: JuntraColors.gold,
                  fontWeight: FontWeight.w600,
                )),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1);
  }
}

class _DailyTransitCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: JuntraColors.mysticHeroGradient,
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        border: Border.all(color: JuntraColors.purple.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                JuntraColors.gold.withValues(alpha: 0.4),
                JuntraColors.gold.withValues(alpha: 0),
              ]),
            ),
            alignment: Alignment.center,
            child: const Text('☾', style: TextStyle(
              fontSize: 26, color: JuntraColors.gold,
            )),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ดาวดวงนี้บอกว่า', style: TextStyle(
                  fontSize: 9, letterSpacing: 2.0,
                  color: JuntraColors.textFaint, fontWeight: FontWeight.w500,
                )),
                const SizedBox(height: 4),
                Text(
                  'พระจันทร์ขึ้นกุมราศีกรกฎ — ลูกจะรู้สึกอ่อนไหว เปิดใจฟังเสียงในหัวใจ',
                  style: const TextStyle(
                    fontSize: 12.5, color: JuntraColors.textLavender, height: 1.5,
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

class _QuickStatsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(child: _Stat(label: 'โควต้าฟรี', value: '3', unit: 'ครั้ง')),
        SizedBox(width: 8),
        Expanded(child: _Stat(label: 'ดูไปแล้ว', value: '12', unit: 'ครั้ง')),
        SizedBox(width: 8),
        Expanded(child: _Stat(label: 'แต้มสะสม', value: '480', unit: 'pt')),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.unit});
  final String label;
  final String value;
  final String unit;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        border: Border.all(color: JuntraColors.purple.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(
            fontSize: 10, color: JuntraColors.textFaint,
          )),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: baiJamjuree(size: 22, color: JuntraColors.gold)),
              const SizedBox(width: 4),
              Text(unit, style: const TextStyle(
                fontSize: 10, color: JuntraColors.textMuted,
              )),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14, fontWeight: FontWeight.w600, color: JuntraColors.textCream,
      ),
    );
  }
}

class _CategoriesGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10,
        childAspectRatio: 2.4,
      ),
      itemCount: fortuneCategories.length,
      itemBuilder: (context, i) {
        final c = fortuneCategories[i];
        return InkWell(
          borderRadius: BorderRadius.circular(JuntraRadius.card),
          onTap: () => context.go('${Routes.spreads}?category=${c.id}'),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [
                  JuntraColors.bgPurpleDeep,
                  JuntraColors.bgPurpleDeep.withValues(alpha: 0.6),
                ],
              ),
              borderRadius: BorderRadius.circular(JuntraRadius.card),
              border: Border.all(color: c.color.withValues(alpha: 0.3)),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -10, top: -10,
                  child: Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        c.glow.withValues(alpha: 0.4),
                        c.glow.withValues(alpha: 0),
                      ]),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Text(c.icon, style: TextStyle(
                      fontSize: 24, color: c.color,
                    )),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(c.name, style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700,
                            color: JuntraColors.textPrimary,
                          )),
                          Text(c.en, style: const TextStyle(
                            fontSize: 10, letterSpacing: 1.5,
                            color: JuntraColors.textFaint,
                          )),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MaeMorOnlineCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: JuntraColors.mysticHeroGradient,
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        border: Border.all(color: JuntraColors.mintGreen.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              ClipOval(
                child: Image.asset(
                  'assets/images/maehmor.png',
                  width: 48, height: 48, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 48, height: 48,
                    color: JuntraColors.bgPurple,
                    alignment: Alignment.center,
                    child: const Text('🔮', style: TextStyle(fontSize: 24)),
                  ),
                ),
              ),
              Container(
                width: 12, height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: JuntraColors.mintGreen,
                  border: Border.all(color: JuntraColors.bgPurpleDeep, width: 2),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('แม่หมอจันทรา · ออนไลน์', style: baiJamjuree(size: 14)),
                const SizedBox(height: 2),
                const Text(
                  'พร้อมตอบคำถามด้วย AI · ตอบใน 8 วิ',
                  style: TextStyle(fontSize: 11, color: JuntraColors.textMuted),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () => context.go(Routes.chat),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: JuntraColors.goldButtonGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'คุยเลย',
                style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: JuntraColors.bgPurpleDeep,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentReadingTile extends StatelessWidget {
  const _RecentReadingTile({
    required this.category, required this.date,
    required this.time, required this.preview,
  });
  final String category;
  final String date;
  final String time;
  final String preview;
  @override
  Widget build(BuildContext context) {
    final cat = fortuneCategories.firstWhere((c) => c.id == category,
        orElse: () => fortuneCategories.last);
    return InkWell(
      onTap: () => context.go(Routes.reading),
      borderRadius: BorderRadius.circular(JuntraRadius.card),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(JuntraRadius.card),
          border: Border.all(color: cat.color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cat.color.withValues(alpha: 0.18),
              ),
              alignment: Alignment.center,
              child: Text(cat.icon, style: TextStyle(
                fontSize: 18, color: cat.color,
              )),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(cat.name, style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600,
                        color: JuntraColors.textCream,
                      )),
                      const SizedBox(width: 6),
                      Text('· $date $time', style: const TextStyle(
                        fontSize: 10, color: JuntraColors.textFaint,
                      )),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    preview,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12, color: JuntraColors.textLavender,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: JuntraColors.gold, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Bottom tab bar — minimal 4-tab design (Home, History, Chat, Profile).
class _JuntraTabBar extends StatelessWidget {
  const _JuntraTabBar({required this.currentIndex});
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: JuntraColors.bgDeepest.withValues(alpha: 0.85),
        border: Border(top: BorderSide(
          color: JuntraColors.gold.withValues(alpha: 0.2),
        )),
      ),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _TabIcon(icon: Icons.home_filled, label: 'หน้าแรก', selected: currentIndex == 0,
              onTap: () => context.go(Routes.home)),
          _TabIcon(icon: Icons.history, label: 'ประวัติ', selected: currentIndex == 1,
              onTap: () => context.go(Routes.history)),
          _TabIcon(icon: Icons.auto_awesome, label: 'แม่หมอ', selected: currentIndex == 2,
              onTap: () => context.go(Routes.chat)),
          _TabIcon(icon: Icons.person, label: 'โปรไฟล์', selected: currentIndex == 3,
              onTap: () => context.go(Routes.profile)),
        ],
      ),
    );
  }
}

class _TabIcon extends StatelessWidget {
  const _TabIcon({
    required this.icon, required this.label,
    required this.selected, required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final color = selected ? JuntraColors.gold : JuntraColors.textFaint;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(
              fontSize: 10, color: color,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            )),
          ],
        ),
      ),
    );
  }
}
