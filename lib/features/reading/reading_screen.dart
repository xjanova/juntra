import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../shared/data/spreads.dart';
import '../../shared/data/tarot_deck.dart';
import '../../shared/widgets/gold_button.dart';
import '../../shared/widgets/starry_background.dart';
import '../../shared/widgets/tarot_card_widgets.dart';

/// Screen 5 — Reading. Drawn cards laid out in spread layout, AI
/// per-card interpretation, overall summary, action row.
///
/// In production, the reading content is fetched from
/// `POST /v1/fortune/read` (see endpoints.dart) which calls the existing
/// FortuneAIService pool on the Laravel backend. Right now we render a
/// sample 3-card love reading from the design's SAMPLE_READING.
class ReadingScreen extends StatelessWidget {
  const ReadingScreen({super.key, required this.spreadId});
  final String spreadId;

  @override
  Widget build(BuildContext context) {
    final spread = spreads.firstWhere(
      (s) => s.id == spreadId,
      orElse: () => spreads.first,
    );

    final picks = <_Pick>[
      _Pick(card: tarotDeck[18], position: 'อดีต',
          reading: 'ในอดีตหัวใจเดินอยู่ในเงาแห่งจันทร์ มีความสับสน '
              'เรื่องที่ไม่ได้พูดออกมาตรงๆ — สัญชาตญาณกำลังบอกความจริง'),
      _Pick(card: tarotDeck[6], position: 'ปัจจุบัน',
          reading: 'ปัจจุบันคู่รักได้บรรจบ ดาวพฤหัสและศุกร์ส่องประกายชัดเจน '
              'ลูกยืนอยู่ที่ทางแยกของหัวใจ — เลือกด้วยความจริงใจ'),
      _Pick(card: tarotDeck[19], position: 'อนาคต',
          reading: 'อนาคตสว่างไสวดั่งดวงตะวัน ความสัมพันธ์จะเบ่งบาน เปิดเผย '
              'มั่นคง — แม่หมอเห็นแสงทองของลูกชัดเจนค่ะ'),
    ];

    return Scaffold(
      body: Stack(
        children: [
          const StarryBackground(density: 60, intensity: 0.7),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left,
                          color: JuntraColors.gold, size: 28),
                      onPressed: () => context.canPop() ? context.pop() : context.go(Routes.home),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(spread.name, style: baiJamjuree(size: 18)),
                          Text('คำทำนาย ${spread.cards} ใบ',
                              style: const TextStyle(
                                fontSize: 11, color: JuntraColors.textFaint,
                              )),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.share_outlined,
                          color: JuntraColors.purpleBright),
                      onPressed: () => context.push(Routes.share),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _CardsRow(picks: picks),
                const SizedBox(height: 18),
                ...picks.map((p) => _PerCardReading(pick: p)),
                const SizedBox(height: 16),
                _SummaryCard(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: GhostButton(
                        label: 'บันทึก',
                        icon: const Icon(Icons.bookmark_border),
                        onPressed: () {},
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GoldButton(
                        label: 'คุยต่อกับแม่หมอ',
                        icon: const Icon(Icons.chat_bubble_outline),
                        onPressed: () => context.push(Routes.chat),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pick {
  _Pick({required this.card, required this.position, required this.reading});
  final TarotCard card;
  final String position;
  final String reading;
}

class _CardsRow extends StatelessWidget {
  const _CardsRow({required this.picks});
  final List<_Pick> picks;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: picks.map((p) {
        return Column(
          children: [
            CardFront(card: p.card, width: 88, height: 145),
            const SizedBox(height: 6),
            Text(p.position, style: const TextStyle(
              fontSize: 11, color: JuntraColors.gold, fontWeight: FontWeight.w600,
            )),
          ],
        );
      }).toList(),
    );
  }
}

class _PerCardReading extends StatelessWidget {
  const _PerCardReading({required this.pick});
  final _Pick pick;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        border: Border.all(color: JuntraColors.purple.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(pick.position, style: const TextStyle(
                fontSize: 10, letterSpacing: 2,
                color: JuntraColors.gold, fontWeight: FontWeight.w600,
              )),
              const SizedBox(width: 8),
              Text('· ${pick.card.thai}', style: const TextStyle(
                fontSize: 12, color: JuntraColors.textCream,
              )),
            ],
          ),
          const SizedBox(height: 6),
          Text(pick.reading, style: const TextStyle(
            fontSize: 13, color: JuntraColors.textLavender, height: 1.6,
          )),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: JuntraColors.mysticHeroGradient,
        borderRadius: BorderRadius.circular(JuntraRadius.hero),
        border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('สรุปคำทำนาย', style: baiJamjuree(size: 16)),
          const SizedBox(height: 8),
          const Text(
            'ดวงความรักของลูกในช่วงนี้กำลังก้าวจากเงาสู่แสง อย่ากลัวที่จะเปิดใจ '
            'ให้ความจริงนำทาง แล้วทุกสิ่งจะเข้าที่อย่างงดงาม ✨',
            style: TextStyle(
              fontSize: 13, color: JuntraColors.textLavender, height: 1.65,
            ),
          ),
          const SizedBox(height: 12),
          const _AdviceList(),
        ],
      ),
    );
  }
}

class _AdviceList extends StatelessWidget {
  const _AdviceList();
  @override
  Widget build(BuildContext context) {
    final items = const [
      'สวมใส่สีชมพูอ่อนหรือพีชในวันพุธและวันศุกร์',
      'ไหว้พระจันทร์คืนวันเพ็ญ ขอพรเรื่องคู่ครอง',
      'พกหินอเมทิสต์หรือโรสควอตซ์ติดตัว',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.map((t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 6, right: 8),
              child: Icon(Icons.circle, size: 5, color: JuntraColors.gold),
            ),
            Expanded(child: Text(t, style: const TextStyle(
              fontSize: 12, color: JuntraColors.textLavender,
            ))),
          ],
        ),
      )).toList(),
    );
  }
}
