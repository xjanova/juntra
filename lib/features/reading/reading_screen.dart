import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/fortune_repository.dart';
import '../../shared/data/spreads.dart';
import '../../shared/data/tarot_deck.dart';
import '../../shared/widgets/gold_button.dart';
import '../../shared/widgets/starry_background.dart';
import '../../shared/widgets/tarot_card_widgets.dart';

/// Screen 5 — Reading detail. Two modes:
///
///   A. **API mode** — when `readingId` is provided, fetch the persisted
///      reading from `GET /v1/history/readings/{id}` and render the cards
///      + AI interpretation that the backend (FortuneAiService) produced.
///      This is the path taken after the shuffle cinematic completes for
///      supported spreads (tarot_three, tarot_celtic).
///
///   B. **Sample mode** — when only `spreadId` is provided and there's no
///      `readingId`, fall back to the original hand-rolled sample reading
///      from the design handoff. Used by spreads that don't have backend
///      support yet (love, year, horseshoe, yes-no) so the cinematic
///      always lands somewhere.
///
/// The "บันทึก" and "คุยต่อกับแม่หมอ" actions sit at the bottom of both
/// modes — for API mode, share/save will eventually carry the reading id
/// through; for now they're identical to the legacy buttons.
class ReadingScreen extends ConsumerWidget {
  const ReadingScreen({super.key, this.spreadId, this.readingId});
  final String? spreadId;
  final int? readingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (readingId != null) {
      return _ApiModeReading(readingId: readingId!);
    }
    return _SampleModeReading(spreadId: spreadId ?? 'three');
  }
}

// ────────────────────────────────────────────────────────────────────
// API MODE — backed by GET /v1/history/readings/{id}
// ────────────────────────────────────────────────────────────────────

class _ApiModeReading extends ConsumerWidget {
  const _ApiModeReading({required this.readingId});
  final int readingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(readingDetailProvider(readingId));
    return Scaffold(
      body: Stack(
        children: [
          const StarryBackground(density: 60, intensity: 0.7),
          SafeArea(
            child: async.when(
              loading: () => _loading(),
              error: (e, _) => _error(context, ref, e),
              data: (reading) => _detail(context, reading),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loading() {
    return Column(
      children: [
        _header(null, null, onBack: null),
        const Expanded(
          child: Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(JuntraColors.gold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _error(BuildContext context, WidgetRef ref, Object e) {
    return Column(
      children: [
        const _BackHeader(title: 'ผลทำนาย'),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off,
                      color: JuntraColors.textFaint, size: 48),
                  const SizedBox(height: 12),
                  const Text('โหลดผลทำนายไม่สำเร็จ',
                      style: TextStyle(
                        fontSize: 14, color: JuntraColors.textCream,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 6),
                  Text(
                    e.toString(),
                    textAlign: TextAlign.center,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11, color: JuntraColors.textFaint,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      backgroundColor: JuntraColors.bgPurpleDeep,
                      foregroundColor: JuntraColors.gold,
                    ),
                    onPressed: () =>
                        ref.invalidate(readingDetailProvider(readingId)),
                    child: const Text('ลองใหม่'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _detail(BuildContext context, Map<String, dynamic> reading) {
    final type = reading['type']?.toString() ?? '';
    final title = _titleFor(type);
    final question = reading['question']?.toString();
    final result = reading['result']?.toString() ?? '';
    final cards = (reading['cards'] is List)
        ? (reading['cards'] as List).whereType<Map>().toList()
        : <Map>[];

    return Column(
      children: [
        _BackHeader(title: title, subtitle: 'คำทำนาย ${cards.length} ใบ'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              if (question != null && question.trim().isNotEmpty)
                _QuestionBubble(question: question),
              const SizedBox(height: 12),
              if (cards.isNotEmpty) _CardsRow(cards: cards),
              const SizedBox(height: 18),
              ...cards.map((c) => _CardInterpretation(card: c)),
              const SizedBox(height: 16),
              _AiSummaryCard(result: result, reading: reading),
              const SizedBox(height: 16),
              _ActionRow(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _header(String? title, String? subtitle, {VoidCallback? onBack}) {
    return _BackHeader(title: title ?? 'ผลทำนาย', subtitle: subtitle);
  }

  static String _titleFor(String type) {
    return switch (type) {
      'tarot_single'   => 'ไพ่ใบเดียว',
      'tarot_three'    => 'อดีต ปัจจุบัน อนาคต',
      'tarot_love'     => 'ความรัก / เนื้อคู่',
      'tarot_career'   => 'การงาน / การเงิน',
      'tarot_decision' => 'ทางแยก / ตัดสินใจ',
      'tarot_celtic'   => 'เซลติกครอส',
      'tarot_year'     => 'พยากรณ์ 12 เดือน',
      'numerology'     => 'ดวงเลขศาสตร์',
      'palmistry'      => 'ดูลายมือ',
      'auspicious'     => 'ฤกษ์ยาม',
      _ => 'คำทำนาย',
    };
  }
}

class _BackHeader extends StatelessWidget {
  const _BackHeader({required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left,
                color: JuntraColors.gold, size: 28),
            onPressed: () =>
                context.canPop() ? context.pop() : context.go(Routes.home),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: baiJamjuree(size: 18)),
                if (subtitle != null)
                  Text(subtitle!, style: const TextStyle(
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
    );
  }
}

class _QuestionBubble extends StatelessWidget {
  const _QuestionBubble({required this.question});
  final String question;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('คำถามของลูก',
              style: TextStyle(
                fontSize: 10, letterSpacing: 2,
                color: JuntraColors.gold, fontWeight: FontWeight.w600,
              )),
          const SizedBox(height: 4),
          Text(question, style: const TextStyle(
            fontSize: 13, color: JuntraColors.textLavender, height: 1.5,
          )),
        ],
      ),
    );
  }
}

class _CardsRow extends StatelessWidget {
  const _CardsRow({required this.cards});
  final List<Map> cards;

  @override
  Widget build(BuildContext context) {
    // For 3-card spreads use space-evenly. For 10-card celtic use a
    // horizontal scroll so cards don't squish unreadably small.
    if (cards.length <= 4) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: cards.map((c) => _CardThumb(card: c, width: 84, height: 140))
            .toList(),
      );
    }
    return SizedBox(
      height: 170,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: [
          for (final c in cards) Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _CardThumb(card: c, width: 78, height: 130),
          ),
        ],
      ),
    );
  }
}

class _CardThumb extends StatelessWidget {
  const _CardThumb({required this.card, required this.width, required this.height});
  final Map card;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final slug = card['slug']?.toString();
    final reversed = card['reversed'] == true;
    final positionLabel = card['position_label']?.toString() ?? '';
    final local = _localFor(slug);

    return Column(
      children: [
        // Rotate the card 180° for reversed picks so the orientation
        // matches what the AI is interpreting.
        Transform.rotate(
          angle: reversed ? 3.14159 : 0,
          child: local != null
              ? CardFront(card: local, width: width, height: height)
              : _CardPlaceholder(width: width, height: height,
                  thai: card['name_th']?.toString() ?? '?'),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: width + 8,
          child: Text(
            positionLabel,
            maxLines: 2, textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10, color: JuntraColors.gold,
              fontWeight: FontWeight.w600, height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _CardPlaceholder extends StatelessWidget {
  const _CardPlaceholder({
    required this.width, required this.height, required this.thai,
  });
  final double width;
  final double height;
  final String thai;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width, height: height,
      decoration: BoxDecoration(
        color: JuntraColors.bgPurpleDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.4)),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(6),
      child: Text(thai,
          textAlign: TextAlign.center,
          maxLines: 3, overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11, color: JuntraColors.gold, height: 1.4,
          )),
    );
  }
}

class _CardInterpretation extends StatelessWidget {
  const _CardInterpretation({required this.card});
  final Map card;

  @override
  Widget build(BuildContext context) {
    final positionLabel = card['position_label']?.toString() ?? '';
    final nameTh = card['name_th']?.toString() ?? '';
    final reversed = card['reversed'] == true;
    final meaning = card['meaning']?.toString() ?? '';

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
              Text(positionLabel.toUpperCase(), style: const TextStyle(
                fontSize: 10, letterSpacing: 2,
                color: JuntraColors.gold, fontWeight: FontWeight.w600,
              )),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '· $nameTh${reversed ? " (กลับหัว)" : ""}',
                  style: const TextStyle(
                    fontSize: 12, color: JuntraColors.textCream,
                  ),
                ),
              ),
            ],
          ),
          if (meaning.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(meaning, style: const TextStyle(
              fontSize: 13, color: JuntraColors.textLavender, height: 1.6,
            )),
          ],
        ],
      ),
    );
  }
}

class _AiSummaryCard extends StatelessWidget {
  const _AiSummaryCard({required this.result, required this.reading});
  final String result;
  final Map<String, dynamic> reading;

  @override
  Widget build(BuildContext context) {
    final timestamp = reading['created_at']?.toString();
    final formatted = _formatTimestamp(timestamp);

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
          Row(
            children: [
              Text('คำทำนายจากแม่หมอ', style: baiJamjuree(size: 16)),
              const Spacer(),
              if (formatted != null)
                Text(formatted, style: const TextStyle(
                  fontSize: 10, color: JuntraColors.textFaint,
                )),
            ],
          ),
          const SizedBox(height: 10),
          if (result.trim().isEmpty)
            const Text(
              'แม่หมอกำลังพิจารณาไพ่ของลูกอยู่ค่ะ · กรุณาลองเปิดอีกครั้งสักครู่',
              style: TextStyle(
                fontSize: 13, color: JuntraColors.textLavender, height: 1.65,
              ),
            )
          else
            Text(result, style: const TextStyle(
              fontSize: 13.5, color: JuntraColors.textLavender, height: 1.7,
            )),
        ],
      ),
    );
  }

  static String? _formatTimestamp(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return null;
    try {
      return DateFormat('d MMM · HH:mm', 'th').format(dt);
    } catch (_) {
      return DateFormat('d MMM · HH:mm').format(dt);
    }
  }
}

class _ActionRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GhostButton(
            label: 'แชร์',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => context.push(Routes.share),
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
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// SAMPLE MODE — legacy hand-rolled reading for unsupported spreads
// ────────────────────────────────────────────────────────────────────

class _SampleModeReading extends StatelessWidget {
  const _SampleModeReading({required this.spreadId});
  final String spreadId;

  @override
  Widget build(BuildContext context) {
    final spread = spreads.firstWhere(
      (s) => s.id == spreadId,
      orElse: () => spreads.first,
    );

    final picks = <_SamplePick>[
      _SamplePick(card: tarotDeck[18], position: 'อดีต',
          reading: 'ในอดีตหัวใจเดินอยู่ในเงาแห่งจันทร์ มีความสับสน '
              'เรื่องที่ไม่ได้พูดออกมาตรงๆ — สัญชาตญาณกำลังบอกความจริง'),
      _SamplePick(card: tarotDeck[6], position: 'ปัจจุบัน',
          reading: 'ปัจจุบันคู่รักได้บรรจบ ดาวพฤหัสและศุกร์ส่องประกายชัดเจน '
              'ลูกยืนอยู่ที่ทางแยกของหัวใจ — เลือกด้วยความจริงใจ'),
      _SamplePick(card: tarotDeck[19], position: 'อนาคต',
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
                      onPressed: () =>
                          context.canPop() ? context.pop() : context.go(Routes.home),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: picks.map((p) => Column(
                    children: [
                      CardFront(card: p.card, width: 88, height: 145),
                      const SizedBox(height: 6),
                      Text(p.position, style: const TextStyle(
                        fontSize: 11, color: JuntraColors.gold,
                        fontWeight: FontWeight.w600,
                      )),
                    ],
                  )).toList(),
                ),
                const SizedBox(height: 18),
                for (final p in picks) Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(JuntraRadius.card),
                    border: Border.all(
                      color: JuntraColors.purple.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(p.position, style: const TextStyle(
                            fontSize: 10, letterSpacing: 2,
                            color: JuntraColors.gold,
                            fontWeight: FontWeight.w600,
                          )),
                          const SizedBox(width: 8),
                          Text('· ${p.card.thai}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: JuntraColors.textCream,
                              )),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(p.reading, style: const TextStyle(
                        fontSize: 13, color: JuntraColors.textLavender,
                        height: 1.6,
                      )),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: JuntraColors.mysticHeroGradient,
                    borderRadius: BorderRadius.circular(JuntraRadius.hero),
                    border: Border.all(
                      color: JuntraColors.gold.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('สรุปคำทำนาย', style: baiJamjuree(size: 16)),
                      const SizedBox(height: 8),
                      const Text(
                        'ดวงความรักของลูกในช่วงนี้กำลังก้าวจากเงาสู่แสง '
                        'อย่ากลัวที่จะเปิดใจ ให้ความจริงนำทาง แล้วทุกสิ่งจะเข้าที่อย่างงดงาม ✨',
                        style: TextStyle(
                          fontSize: 13, color: JuntraColors.textLavender,
                          height: 1.65,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _ActionRow(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SamplePick {
  _SamplePick({
    required this.card, required this.position, required this.reading,
  });
  final TarotCard card;
  final String position;
  final String reading;
}

// ────────────────────────────────────────────────────────────────────
// Shared helpers
// ────────────────────────────────────────────────────────────────────

/// Resolve a server-side `slug` to the local [TarotCard] entry (so we
/// can render its art + symbol). Local deck doesn't store slugs directly;
/// we compare against the derived [TarotCard.slug].
TarotCard? _localFor(String? slug) {
  if (slug == null || slug.isEmpty) return null;
  for (final card in tarotDeck) {
    if (card.slug == slug) return card;
  }
  return null;
}
