import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/fortune_repository.dart';
import '../../core/api/report_repository.dart';
import '../../core/auth/auth_state.dart';
import '../../shared/data/tarot_deck.dart';
import '../../shared/widgets/gold_button.dart';
import '../../shared/widgets/report_content_sheet.dart';
import '../../shared/widgets/starry_background.dart';
import '../../shared/widgets/tarot_card_widgets.dart';
import 'reading_sections_view.dart';

/// Screen 5 — ผลคำทำนาย (`GET /v1/history/readings/{id}`)
///
/// ไพ่ที่ซื้อจากแอพรุ่นนี้ใช้ `mode: async` — เซิร์ฟเวอร์ตัดเงินแล้วตอบทันที แม่หมออ่านไพ่
/// เบื้องหลัง (แพ็กเกจยาว 36-55 วิ) หน้านี้จึงถาม `/status` ทุก 3 วิจนเสร็จ แล้วค่อยดึงผลเต็ม
/// ไม่สำเร็จ = เซิร์ฟเวอร์คืนเงินแล้ว (TarotReadingFinisher) หน้านี้บอกลูกค้าและรีเฟรชยอด
///
/// โหมด "คำทำนายตัวอย่าง" ที่ฝังข้อความไว้ในแอพถูกลบทิ้งแล้ว — แสดงคำทำนายปลอมเหมือนจริง
/// ขัดนโยบาย Deceptive Behavior ของ Google Play และทุกแพ็กเกจอ่านจากเซิร์ฟเวอร์ได้หมดแล้ว
class ReadingScreen extends ConsumerWidget {
  const ReadingScreen({super.key, this.readingId});
  final int? readingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = readingId;
    if (id == null) return const _NoReading();
    return _ApiModeReading(readingId: id);
  }
}

// ────────────────────────────────────────────────────────────────────
// API MODE — backed by GET /v1/history/readings/{id}
// ────────────────────────────────────────────────────────────────────

class _ApiModeReading extends ConsumerStatefulWidget {
  const _ApiModeReading({required this.readingId});
  final int readingId;

  @override
  ConsumerState<_ApiModeReading> createState() => _ApiModeReadingState();
}

class _ApiModeReadingState extends ConsumerState<_ApiModeReading> {
  /// ถามทุก 3 วิเหมือนหน้าเว็บ — เลิกถามที่ 4 นาที (ตัวกวาดฝั่งเซิร์ฟเวอร์คืนเงินรายการค้างใน ~5-10 นาที)
  static const _pollEvery = Duration(seconds: 3);
  static const _giveUpAfter = Duration(minutes: 4);

  Timer? _timer;
  DateTime? _pollStarted;
  bool _checking = false;
  bool _gaveUp = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _ensurePolling() {
    if (_timer != null || _gaveUp) return;
    _pollStarted ??= DateTime.now();
    _timer = Timer.periodic(_pollEvery, (_) => _tick());
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (_checking || !mounted) return;
    if (DateTime.now().difference(_pollStarted!) > _giveUpAfter) {
      _stopPolling();
      setState(() => _gaveUp = true);
      return;
    }
    _checking = true;
    try {
      final repo = await ref.read(fortuneRepositoryProvider.future);
      final status = await repo.readingStatus(widget.readingId);
      if (!mounted) return;
      if (status == 'done' || status == 'failed') {
        _stopPolling();
        ref.invalidate(readingDetailProvider(widget.readingId));
        ref.invalidate(fortuneHistoryProvider);
        // ไม่สำเร็จ = เซิร์ฟเวอร์คืนเครดิตแล้ว — ยอดบนหน้าแรก/วอลเลตต้องกลับมาทันที
        if (status == 'failed') {
          // ignore: unawaited_futures
          ref.read(authControllerProvider.notifier).refresh();
        }
      }
    } catch (_) {
      // สัญญาณหลุดชั่วคราว — รอบถัดไปถามใหม่
    } finally {
      _checking = false;
    }
  }

  Future<void> _retryAfterGiveUp() async {
    setState(() {
      _gaveUp = false;
      _pollStarted = DateTime.now();
    });
    ref.invalidate(readingDetailProvider(widget.readingId));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(readingDetailProvider(widget.readingId));
    return Scaffold(
      body: Stack(
        children: [
          const StarryBackground(density: 60, intensity: 0.7),
          SafeArea(
            child: async.when(
              loading: () => const Column(
                children: [
                  _BackHeader(title: 'ผลทำนาย'),
                  Expanded(
                    child: Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(JuntraColors.gold),
                      ),
                    ),
                  ),
                ],
              ),
              error: (e, _) => _error(e),
              data: (reading) {
                final status = reading['status']?.toString() ?? 'done';
                if (status == 'pending' || status == 'working') {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _ensurePolling();
                  });
                } else {
                  _stopPolling();
                }
                return _detail(reading, status);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _error(Object e) {
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
                  const Icon(Icons.cloud_off, color: JuntraColors.textFaint, size: 48),
                  const SizedBox(height: 12),
                  const Text('โหลดผลทำนายไม่สำเร็จ',
                      style: TextStyle(fontSize: 14, color: JuntraColors.textCream, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  const Text('ตรวจสอบสัญญาณอินเทอร์เน็ต แล้วลองใหม่อีกครั้ง',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11.5, color: JuntraColors.textFaint)),
                  const SizedBox(height: 16),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      backgroundColor: JuntraColors.bgPurpleDeep,
                      foregroundColor: JuntraColors.gold,
                    ),
                    onPressed: () => ref.invalidate(readingDetailProvider(widget.readingId)),
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

  Widget _detail(Map<String, dynamic> reading, String status) {
    final type = reading['type']?.toString() ?? '';
    final title = reading['title']?.toString() ?? _titleFor(type);
    final question = reading['question']?.toString();
    final result = reading['result']?.toString() ?? '';
    final cards = (reading['cards'] is List)
        ? (reading['cards'] as List).whereType<Map>().toList()
        : <Map>[];
    final readingId = (reading['id'] as num?)?.toInt();
    final package = reading['package'] is Map ? Map<String, dynamic>.from(reading['package'] as Map) : null;
    final sections = reading['sections'] is Map ? Map<String, dynamic>.from(reading['sections'] as Map) : null;
    final sectionItems = (sections?['ok'] == true && sections?['items'] is List)
        ? (sections!['items'] as List).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
        : const <Map<String, dynamic>>[];
    final isTarot = type.startsWith('tarot_');
    final done = status == 'done';

    // 🔴 'คำทำนาย N ใบ' ใช้ได้เฉพาะไพ่ — เซิร์ฟเวอร์คืน cards = [] ให้ทุกหมวด
    // ที่ไม่ขึ้นต้นด้วย tarot_ เลขศาสตร์/ลายมือ/ฤกษ์/เชิงลึกจึงขึ้น
    // 'คำทำนาย 0 ใบ' เสมอ ดูเหมือนผลว่างเปล่าทั้งที่คำทำนายมาครบ
    final subtitle = isTarot
        ? 'คำทำนาย ${cards.length} ใบ'
        : (question != null && question.trim().isNotEmpty
            ? question.trim()
            : _readingDateLabel(reading['created_at']?.toString()));

    final canReport = done && readingId != null && result.trim().isNotEmpty;

    return Column(
      children: [
        _BackHeader(
          title: title,
          subtitle: subtitle,
          readingId: done ? readingId : null,
          onReport: canReport
              ? () => ReportContentSheet.show(context, subject: ReportSubject.reading, subjectId: readingId)
              : null,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              if (package?['image_url'] is String) _PackageBanner(url: package!['image_url'] as String),
              if (question != null && question.trim().isNotEmpty)
                _QuestionBubble(question: question),
              const SizedBox(height: 12),
              // รูปฝ่ามือที่ลูกค้าอัปโหลด — ต้องเห็นเพื่อตรวจได้ว่าแม่หมออ่านจาก
              // รูปที่ถูกต้อง (เซิร์ฟเวอร์ส่ง image_url เป็น absolute มาให้แล้ว)
              if ((reading['image_url']?.toString() ?? '').isNotEmpty)
                _PalmPhoto(url: reading['image_url'].toString()),
              if (type == 'numerology') _NumerologyNumbers(payload: reading['payload']),
              if (type == 'auspicious') _AuspiciousDays(payload: reading['payload']),
              if (cards.isNotEmpty) _CardsRow(cards: cards),
              const SizedBox(height: 18),
              if (status == 'pending' || status == 'working')
                _PendingPanel(gaveUp: _gaveUp, onRetry: _retryAfterGiveUp)
              else if (status == 'failed')
                _FailedPanel(spreadKey: package?['key']?.toString())
              else if (sectionItems.isNotEmpty) ...[
                ReadingSectionsView(items: sectionItems),
              ] else ...[
                ...cards.map((c) => _CardInterpretation(card: c)),
                const SizedBox(height: 16),
                _AiSummaryCard(result: result, reading: reading),
              ],
              const SizedBox(height: 16),
              if (done) _ActionRow(readingId: readingId, isTarot: isTarot),
              if (canReport) _AiNotice(onReport: () => ReportContentSheet.show(context, subject: ReportSubject.reading, subjectId: readingId)),
            ],
          ),
        ),
      ],
    );
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
      'tarot_kunsai'   => 'ไพ่ดูคุณไสย / โดนของ',
      'numerology'     => 'ดวงเลขศาสตร์',
      'palmistry'      => 'ดูลายมือ',
      'auspicious'     => 'ฤกษ์ยาม',
      'deep'           => 'ดูดวงเชิงลึก',
      _ => 'คำทำนาย',
    };
  }
}

/// แม่หมอกำลังอ่านไพ่ (อ่านเบื้องหลัง) — ถามสถานะทุก 3 วิ
class _PendingPanel extends StatelessWidget {
  const _PendingPanel({required this.gaveUp, required this.onRetry});
  final bool gaveUp;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: JuntraColors.mysticHeroGradient,
        borderRadius: BorderRadius.circular(JuntraRadius.hero),
        border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          if (!gaveUp) ...[
            const SizedBox(
              width: 44, height: 44,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: JuntraColors.gold),
            ),
            const SizedBox(height: 16),
            Text('แม่หมอกำลังอ่านไพ่ของลูก...', style: baiJamjuree(size: 17, color: JuntraColors.gold)),
            const SizedBox(height: 8),
            const Text(
              'แพ็กเกจที่ลึกใช้เวลาราวหนึ่งนาที · ออกจากหน้านี้ได้ คำทำนายจะอยู่ในประวัติเมื่อเสร็จ',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: JuntraColors.textLavender, height: 1.6),
            ),
          ] else ...[
            const Icon(Icons.hourglass_bottom_rounded, color: JuntraColors.gold, size: 36),
            const SizedBox(height: 12),
            Text('ยังอ่านไม่เสร็จ', style: baiJamjuree(size: 17, color: JuntraColors.gold)),
            const SizedBox(height: 8),
            const Text(
              'ระบบกำลังตรวจสอบให้ ถ้าไม่สำเร็จเครดิตจะคืนเข้าวอลเลตอัตโนมัติภายในไม่กี่นาที',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: JuntraColors.textLavender, height: 1.6),
            ),
            const SizedBox(height: 14),
            GhostButton(label: 'ตรวจอีกครั้ง', onPressed: onRetry),
          ],
        ],
      ),
    );
  }
}

/// อ่านไม่สำเร็จ — เซิร์ฟเวอร์คืนเครดิตให้แล้ว
class _FailedPanel extends StatelessWidget {
  const _FailedPanel({this.spreadKey});
  final String? spreadKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(JuntraRadius.hero),
        border: Border.all(color: const Color(0xFFFF8FA0).withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFFFF8FA0), size: 36),
          const SizedBox(height: 12),
          Text('แม่หมออ่านไพ่ชุดนี้ไม่สำเร็จ', style: baiJamjuree(size: 17, color: JuntraColors.textCream)),
          const SizedBox(height: 8),
          const Text(
            'เครดิตถูกคืนเข้าวอลเลตเรียบร้อยแล้ว ลองเปิดไพ่ใหม่อีกครั้งได้เลยค่ะ',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: JuntraColors.textLavender, height: 1.6),
          ),
          const SizedBox(height: 14),
          GoldButton(
            label: 'เปิดไพ่ใหม่',
            onPressed: () => context.pushReplacement(
              spreadKey == null ? Routes.spreads : '${Routes.shuffle}?spread=$spreadKey',
            ),
          ),
        ],
      ),
    );
  }
}

class _PackageBanner extends StatelessWidget {
  const _PackageBanner({required this.url});
  final String url;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        child: AspectRatio(
          aspectRatio: 16 / 7,
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            errorWidget: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

/// เนื้อหาสร้างโดย AI + ทางรายงาน (Google Play: AI-Generated Content policy)
class _AiNotice extends StatelessWidget {
  const _AiNotice({required this.onReport});
  final VoidCallback onReport;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'คำทำนายสร้างโดย AI เพื่อความบันเทิงและเป็นแนวทางไตร่ตรอง ไม่ใช่คำแนะนำทางการแพทย์ กฎหมาย หรือการเงิน',
              style: TextStyle(fontSize: 10.5, color: JuntraColors.textFaint, height: 1.5),
            ),
          ),
          TextButton.icon(
            onPressed: onReport,
            icon: const Icon(Icons.flag_outlined, size: 14),
            label: const Text('รายงาน', style: TextStyle(fontSize: 11.5)),
            style: TextButton.styleFrom(foregroundColor: JuntraColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _NoReading extends StatelessWidget {
  const _NoReading();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const StarryBackground(density: 60, intensity: 0.7),
          SafeArea(
            child: Column(
              children: [
                const _BackHeader(title: 'ผลทำนาย'),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('ไม่พบคำทำนายนี้',
                              style: TextStyle(fontSize: 15, color: JuntraColors.textCream)),
                          const SizedBox(height: 16),
                          GoldButton(label: 'เลือกแพ็กเกจไพ่', onPressed: () => context.go(Routes.spreads)),
                        ],
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

class _BackHeader extends StatelessWidget {
  const _BackHeader({required this.title, this.subtitle, this.readingId, this.onReport});
  final int? readingId;
  final String title;
  final String? subtitle;
  final VoidCallback? onReport;

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
          if (readingId != null)
            IconButton(
              icon: const Icon(Icons.share_outlined,
                  color: JuntraColors.purpleBright),
              onPressed: () => context.push('${Routes.share}?id=$readingId'),
            ),
          if (onReport != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: JuntraColors.purpleBright),
              color: JuntraColors.bgPurpleDeep,
              onSelected: (_) => onReport!(),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'report',
                  child: Row(
                    children: [
                      Icon(Icons.flag_outlined, color: JuntraColors.textMuted, size: 18),
                      SizedBox(width: 10),
                      Text('รายงานคำทำนายนี้', style: TextStyle(color: JuntraColors.textCream)),
                    ],
                  ),
                ),
              ],
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
                fontSize: 10,
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
    final imageUrl = card['image_url']?.toString();
    final local = _localFor(slug);

    return Column(
      children: [
        // Prefer the real web art the backend resolved (image_url), falling
        // back to the built-in drawing per card. CardFace rotates the whole
        // card 180° for reversed picks so it matches the AI interpretation.
        local != null
            ? CardFace(
                card: local,
                imageUrl: (imageUrl != null && imageUrl.isNotEmpty) ? imageUrl : null,
                width: width,
                height: height,
                reversed: reversed,
              )
            : Transform.rotate(
                angle: reversed ? 3.14159 : 0,
                child: _CardPlaceholder(width: width, height: height,
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
                fontSize: 10,
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
            // เซิร์ฟเวอร์ส่ง markdown มา (เลขศาสตร์ใช้ **ตัวหนา** เป็นปกติ)
            // ของเดิมเป็น Text ธรรมดา ผู้ใช้จึงเห็น `**คุณสมชาย**` ดอกจันค้าง
            // ทั้งที่หน้าเชิงลึกในแอพเดียวกันใช้ MarkdownBody อยู่แล้ว
            MarkdownBody(
              data: result,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(
                  fontSize: 13.5, color: JuntraColors.textLavender, height: 1.7,
                ),
                strong: const TextStyle(
                  fontWeight: FontWeight.w700, color: JuntraColors.textCream,
                ),
                listBullet: const TextStyle(
                  fontSize: 13.5, color: JuntraColors.textLavender, height: 1.7,
                ),
                h1: baiJamjuree(size: 17, color: JuntraColors.gold),
                h2: baiJamjuree(size: 15.5, color: JuntraColors.gold),
                h3: baiJamjuree(size: 14.5, color: JuntraColors.gold),
              ),
            ),
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
  const _ActionRow({this.readingId, this.isTarot = false});
  final int? readingId;
  final bool isTarot;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GhostButton(
            label: 'แชร์',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => context.push(
                '${Routes.share}${readingId == null ? '' : '?id=$readingId'}'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GoldButton(
            label: 'คุยต่อกับแม่หมอ',
            icon: const Icon(Icons.chat_bubble_outline),
            // ไพ่ที่จ่ายแล้ว: เปิดห้องที่แม่หมอเห็นไพ่+คำพยากรณ์ชุดนี้ (เหมือนเว็บ)
            // เดิมเปิดแชทเปล่า ลูกค้าต้องเล่าไพ่ใหม่ทั้งหมด
            onPressed: () => context.push(
              isTarot && readingId != null
                  ? '${Routes.chat}?reading=$readingId'
                  : Routes.chat,
            ),
          ),
        ),
      ],
    );
  }
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

/// วันที่ของคำทำนาย — ใช้เป็นบรรทัดรองของหมวดที่ไม่ใช่ไพ่
String? _readingDateLabel(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return null;
  try {
    return DateFormat('d MMMM y', 'th').format(dt);
  } catch (_) {
    return DateFormat('d MMM y').format(dt);
  }
}

/// รูปฝ่ามือที่ลูกค้าส่งมา
class _PalmPhoto extends StatelessWidget {
  const _PalmPhoto({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        child: Image.network(
          url,
          height: 220,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// เลขศาสตร์ 3 ตัวหลัก — ชุดเดียวกับที่หน้าผลของเว็บโชว์
class _NumerologyNumbers extends StatelessWidget {
  const _NumerologyNumbers({required this.payload});
  final dynamic payload;

  @override
  Widget build(BuildContext context) {
    final p = payload is Map ? Map<String, dynamic>.from(payload as Map) : const {};
    final items = <(String, dynamic)>[
      ('เลขชีวิต', p['life_path']),
      ('เลขนาม', p['expression']),
      ('เลขวันเกิด', p['birth_day_reduced'] ?? p['birth_day']),
    ].where((e) => e.$2 != null).toList();

    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          for (final (label, value) in items)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: JuntraColors.purpleCardGradient,
                  borderRadius: BorderRadius.circular(JuntraRadius.card),
                  border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Text('$value', style: baiJamjuree(size: 26, color: JuntraColors.gold)),
                    const SizedBox(height: 2),
                    Text(label, style: const TextStyle(
                      fontSize: 10.5, color: JuntraColors.textMuted,
                    )),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// วันมงคลที่แม่หมอเลือกให้ — อ่านจาก `payload.candidates` ที่เซิร์ฟเวอร์ส่งมาครบ
class _AuspiciousDays extends StatelessWidget {
  const _AuspiciousDays({required this.payload});
  final dynamic payload;

  @override
  Widget build(BuildContext context) {
    final p = payload is Map ? Map<String, dynamic>.from(payload as Map) : const {};
    final raw = p['candidates'];
    if (raw is! List || raw.isEmpty) return const SizedBox.shrink();

    // โชว์ 3 วันแรก — ที่เหลืออยู่ในเนื้อคำทำนายอยู่แล้ว
    final days = raw.whereType<Map>().take(3).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final d in days) _dayCard(Map<String, dynamic>.from(d)),
        ],
      ),
    );
  }

  Widget _dayCard(Map<String, dynamic> d) {
    final pct = (d['score_pct'] as num?)?.round();
    final rows = <(String, String?)>[
      ('ฤกษ์บน', _text(d['ruek'])),
      ('ดิถี', _text(d['tithi'])),
      ('นักษัตร', _text(d['nakshatra'])),
      ('ยาม', _text(d['yam'])),
    ].where((e) => e.$2 != null && e.$2!.isNotEmpty).toList();

    final from = d['ruek_from']?.toString();
    final to = d['ruek_to']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: JuntraColors.purpleCardGradient,
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(d['label']?.toString() ?? d['date']?.toString() ?? '',
                    style: baiJamjuree(size: 15)),
              ),
              if (pct != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: JuntraColors.gold.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('$pct%', style: const TextStyle(
                    fontSize: 12, color: JuntraColors.gold, fontWeight: FontWeight.w700,
                  )),
                ),
            ],
          ),
          if (from != null && to != null && from.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('ช่วงฤกษ์ $from–$to น.',
                style: const TextStyle(fontSize: 11.5, color: JuntraColors.cyan)),
          ],
          const SizedBox(height: 8),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 62,
                    child: Text(label, style: const TextStyle(
                      fontSize: 11, color: JuntraColors.textFaint,
                    )),
                  ),
                  Expanded(
                    child: Text(value!, style: const TextStyle(
                      fontSize: 12, color: JuntraColors.textLavender, height: 1.5,
                    )),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// ค่าบางช่องเป็น map (เช่น tithi = {label, ...}) บางช่องเป็นสตริง
  static String? _text(dynamic v) {
    if (v == null) return null;
    if (v is Map) return (v['label'] ?? v['name'] ?? '').toString();
    return v.toString();
  }
}
