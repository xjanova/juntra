import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/fortune_repository.dart';
import '../../core/auth/auth_state.dart';
import '../../shared/data/fortune_categories.dart';
import '../../shared/data/tarot_deck.dart';
import '../../shared/widgets/juntra_tab_bar.dart';
import '../../shared/widgets/pill.dart';
import '../../shared/widgets/starry_background.dart';
import '../../shared/widgets/tarot_card_widgets.dart';
import '../../shared/widgets/xman_studio_footer.dart';

/// Screen 2 — Home. Daily card hero, daily transit reading, quick stats,
/// fortune categories grid (2×4), Mae Mor online card, recent readings.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                const _SectionLabel('หมวดดูดวง'),
                const SizedBox(height: 10),
                _CategoriesGrid(),
                const SizedBox(height: 18),
                _MaeMorOnlineCard(),
                const SizedBox(height: 18),
                _RecentReadingsSection(),
                const SizedBox(height: 24),
                const Center(child: XmanStudioFooter()),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const JuntraTabBar(currentIndex: 0),
    );
  }
}

class _Greeting extends ConsumerWidget {
  const _Greeting({required this.weekday});
  final String weekday;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final name = auth is AuthAuthenticated ? auth.displayName : 'แขก';
    // Grapheme-safe first letter (runes handle surrogate pairs / emoji names).
    final initial =
        name.runes.isEmpty ? '?' : String.fromCharCode(name.runes.first);
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
              Text('$name ✨', style: baiJamjuree(size: 22)),
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
          child: Text(initial, style: const TextStyle(
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
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ดาวดวงนี้บอกว่า', style: TextStyle(
                  fontSize: 9, letterSpacing: 2.0,
                  color: JuntraColors.textFaint, fontWeight: FontWeight.w500,
                )),
                SizedBox(height: 4),
                Text(
                  'พระจันทร์ขึ้นกุมราศีกรกฎ — ลูกจะรู้สึกอ่อนไหว เปิดใจฟังเสียงในหัวใจ',
                  style: TextStyle(
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

/// Real wallet balance (member) or a sign-in invite (guest) — replaces the
/// old hardcoded quota/used/points placeholders that showed the same fake
/// numbers to everyone.
class _QuickStatsRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);

    if (auth is AuthAuthenticated) {
      final symbol = auth.walletCurrency == 'THB' ? '฿' : auth.walletCurrency;
      final balance = auth.walletBalance ?? 0;
      return InkWell(
        onTap: () => context.push(Routes.wallet),
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            gradient: JuntraColors.purpleCardGradient,
            borderRadius: BorderRadius.circular(JuntraRadius.card),
            border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  color: JuntraColors.gold, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('เครดิตคงเหลือ',
                        style: TextStyle(
                          fontSize: 10, letterSpacing: 1.4,
                          color: JuntraColors.textFaint,
                        )),
                    const SizedBox(height: 2),
                    Text(
                      '$symbol${NumberFormat.decimalPattern('th').format(balance)}',
                      style: baiJamjuree(size: 22, color: JuntraColors.gold),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: JuntraColors.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('เติมเครดิต',
                    style: TextStyle(
                      fontSize: 12, color: JuntraColors.gold,
                      fontWeight: FontWeight.w700,
                    )),
              ),
            ],
          ),
        ),
      );
    }

    // Guest — invite sign-in instead of fabricated stats.
    return InkWell(
      onTap: () => context.push(Routes.login),
      borderRadius: BorderRadius.circular(JuntraRadius.card),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          gradient: JuntraColors.mysticHeroGradient,
          borderRadius: BorderRadius.circular(JuntraRadius.card),
          border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.3)),
        ),
        child: const Row(
          children: [
            Icon(Icons.lock_open_outlined, color: JuntraColors.gold, size: 22),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'เข้าสู่ระบบเพื่อเก็บประวัติคำทำนายและเครดิตของคุณ',
                style: TextStyle(
                  fontSize: 12.5, color: JuntraColors.textCream, height: 1.4,
                ),
              ),
            ),
            Icon(Icons.arrow_forward_rounded, color: JuntraColors.gold, size: 18),
          ],
        ),
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
          onTap: () => context.push('${Routes.spreads}?category=${c.id}'),
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
                  errorBuilder: (_, _, _) => Container(
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
            onTap: () => context.push(Routes.chat),
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

/// "ดูดวงล่าสุดของลูก" — pulls the first 3 entries from
/// [fortuneHistoryProvider]. For guests we hide the section entirely
/// (rather than show a sign-in nag inline) since the home screen has
/// plenty else to land on. On error / empty we show a one-line nudge to
/// open the History tab; loading is silently elided because the home
/// screen is already busy with the daily card hero above.
class _RecentReadingsSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    if (auth is! AuthAuthenticated) {
      return const SizedBox.shrink();
    }
    final async = ref.watch(fortuneHistoryProvider);

    final rows = async.maybeWhen(
      data: (list) => list,
      orElse: () => const <dynamic>[],
    );
    final topThree = rows.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const _SectionLabel('ดูดวงล่าสุดของลูก'),
            const Spacer(),
            if (topThree.isNotEmpty)
              InkWell(
                onTap: () => context.push(Routes.history),
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text('ดูทั้งหมด →', style: TextStyle(
                    fontSize: 11, color: JuntraColors.gold,
                    fontWeight: FontWeight.w600,
                  )),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (async.isLoading && topThree.isEmpty)
          Container(
            height: 64, alignment: Alignment.center,
            child: const SizedBox(
              width: 22, height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(JuntraColors.gold),
              ),
            ),
          )
        else if (topThree.isEmpty)
          _emptyHint(context)
        else
          for (final r in topThree)
            if (r is Map) Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RecentReadingTile(reading: r),
            ),
      ],
    );
  }

  Widget _emptyHint(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        border: Border.all(color: JuntraColors.purple.withValues(alpha: 0.18)),
      ),
      child: const Row(
        children: [
          Icon(Icons.auto_awesome,
              color: JuntraColors.gold, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'ยังไม่มีคำทำนาย · เริ่มเปิดไพ่ใบแรกของลูกได้เลย',
              style: TextStyle(
                fontSize: 12, color: JuntraColors.textMuted, height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentReadingTile extends StatelessWidget {
  const _RecentReadingTile({required this.reading});
  final Map reading;

  static const Map<String, (String, String, Color)> _typeMeta = {
    'tarot_single':   ('ไพ่ใบเดียว',  '✦', JuntraColors.gold),
    'tarot_three':    ('ทาโรต์ 3 ใบ', '✦', JuntraColors.gold),
    'tarot_love':     ('ความรัก',     '♥', Color(0xFFFF6B9D)),
    'tarot_career':   ('การงาน-เงิน', '✦', JuntraColors.gold),
    'tarot_decision': ('ทางแยก',      '✧', JuntraColors.purpleBright),
    'tarot_celtic':   ('เซลติกครอส',   '✧', JuntraColors.purpleBright),
    'tarot_year':     ('ดวง 12 เดือน', '☾', JuntraColors.gold),
    'numerology':     ('เลขศาสตร์',    '⊛', JuntraColors.mintGreen),
    'palmistry':      ('ดูลายมือ',     '✋', JuntraColors.gold),
    'auspicious':     ('ฤกษ์ยาม',     '☼', JuntraColors.cyan),
  };

  @override
  Widget build(BuildContext context) {
    final type = reading['type']?.toString() ?? '';
    final meta = _typeMeta[type] ?? ('คำทำนาย', '✦', JuntraColors.gold);
    final id = (reading['id'] as num?)?.toInt();
    final preview = reading['preview']?.toString() ?? '';
    final relative = _relativeTime(reading['created_at']?.toString());

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: id == null ? null : () => context.push('${Routes.reading}?id=$id'),
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(JuntraRadius.card),
            border: Border.all(color: meta.$3.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: meta.$3.withValues(alpha: 0.18),
                ),
                alignment: Alignment.center,
                child: Text(meta.$2, style: TextStyle(
                  fontSize: 18, color: meta.$3,
                )),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(meta.$1, style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600,
                          color: JuntraColors.textCream,
                        )),
                        if (relative != null) ...[
                          const SizedBox(width: 6),
                          Text('· $relative', style: const TextStyle(
                            fontSize: 10, color: JuntraColors.textFaint,
                          )),
                        ],
                      ],
                    ),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        preview,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12, color: JuntraColors.textLavender,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: JuntraColors.gold, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  static String? _relativeTime(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return null;
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'เมื่อสักครู่';
    if (diff.inMinutes < 60) return '${diff.inMinutes} นาทีก่อน';
    if (diff.inHours < 24) return '${diff.inHours} ชั่วโมงก่อน';
    if (diff.inDays < 7) return '${diff.inDays} วันก่อน';
    try {
      return DateFormat('d MMM', 'th').format(dt);
    } catch (_) {
      return DateFormat('d MMM').format(dt);
    }
  }
}

