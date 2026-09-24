import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../app/theme.dart';

/// คำทำนายไพ่แบบแยกชิ้น (การ์ด/ตาราง) — ชุดเดียวกับหน้าผลบนเว็บ
///
/// เซิร์ฟเวอร์แยกคำตอบของแม่หมอตาม "หัวข้อตายตัว" ของแต่ละแพ็กเกจ (App\Support\ReadingSections)
/// แล้วส่ง `sections.items` มาให้ — ฟันธง · รายใบ · รายเดือน · ใจเรา/ใจเขา · ทางเลือก ·
/// วินิจฉัย/ทางแก้ (คุณไสย) · ข้อควรระวัง · คำแนะนำ ฯลฯ แอพไม่แยกข้อความเองซ้ำ
class ReadingSectionsView extends StatelessWidget {
  const ReadingSectionsView({super.key, required this.items});
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    final months = items.where((s) => s['type'] == 'month').toList();
    final others = items.where((s) => s['type'] != 'month').toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in others) ...[
          _SectionCard(section: s),
          const SizedBox(height: 10),
        ],
        if (months.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4, bottom: 8),
            child: Text('รายเดือน', style: baiJamjuree(size: 15, color: JuntraColors.gold)),
          ),
          for (final m in months) ...[
            _MonthCard(section: m),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section});
  final Map<String, dynamic> section;

  static const _icons = <String, IconData>{
    'verdict': Icons.gps_fixed_rounded,
    'card': Icons.style_outlined,
    'story': Icons.menu_book_outlined,
    'hearts': Icons.favorite_border_rounded,
    'timing': Icons.hourglass_bottom_rounded,
    'option': Icons.alt_route_rounded,
    'choice': Icons.check_circle_outline_rounded,
    'golden': Icons.auto_awesome_outlined,
    'caution': Icons.warning_amber_rounded,
    'birth': Icons.cake_outlined,
    'diagnosis': Icons.visibility_outlined,
    'detail': Icons.search_rounded,
    'remedy': Icons.spa_outlined,
    'direction': Icons.explore_outlined,
    'safety': Icons.support_agent_outlined,
    'advice': Icons.lightbulb_outline_rounded,
  };

  Color _accent(String type) => switch (type) {
        'verdict' || 'diagnosis' => JuntraColors.gold,
        'caution' || 'safety' => const Color(0xFFFFB86B),
        'golden' || 'remedy' => JuntraColors.mintGreen,
        'hearts' => const Color(0xFFFF8FB1),
        'option' || 'choice' => JuntraColors.cyan,
        _ => JuntraColors.purpleBright,
      };

  @override
  Widget build(BuildContext context) {
    final type = section['type']?.toString() ?? '';
    final accent = _accent(type);
    final title = _title(type);
    final result = section['result']?.toString();
    final fields = section['fields'] is Map
        ? Map<String, dynamic>.from(section['fields'] as Map)
        : const <String, dynamic>{};
    final items = section['items'] is List
        ? (section['items'] as List).map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : const <String>[];
    final body = section['body']?.toString().trim() ?? '';
    final chosen = (section['chosen'] as num?)?.toInt();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        gradient: type == 'verdict' ? JuntraColors.mysticHeroGradient : null,
        color: type == 'verdict' ? null : JuntraColors.bgPurpleDeep.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        border: Border.all(color: accent.withValues(alpha: type == 'verdict' ? 0.6 : 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icons[type] ?? Icons.auto_awesome_outlined, color: accent, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: baiJamjuree(size: 15, color: accent))),
            ],
          ),
          if (result != null && result.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(result, style: baiJamjuree(size: 20, color: _verdictColor(result))),
          ],
          if (chosen != null) ...[
            const SizedBox(height: 6),
            Text('แม่หมอเลือกทางที่ $chosen', style: baiJamjuree(size: 16, color: JuntraColors.cyan)),
          ],
          if (fields.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final e in fields.entries)
              if ('${e.value}'.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 92,
                        child: Text(e.key, style: TextStyle(fontSize: 12, color: accent, fontWeight: FontWeight.w600)),
                      ),
                      Expanded(
                        child: Text('${e.value}', style: const TextStyle(fontSize: 13, color: JuntraColors.textLavender, height: 1.5)),
                      ),
                    ],
                  ),
                ),
          ],
          if (items.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final it in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 8),
                      child: Icon(Icons.circle, size: 6, color: accent),
                    ),
                    Expanded(
                      child: Text(it, style: const TextStyle(fontSize: 13, color: JuntraColors.textLavender, height: 1.55)),
                    ),
                  ],
                ),
              ),
          ],
          if (body.isNotEmpty) ...[
            const SizedBox(height: 6),
            MarkdownBody(data: body, selectable: true, styleSheet: _md()),
          ],
        ],
      ),
    );
  }

  String _title(String type) {
    final t = section['title']?.toString() ?? '';
    if (type == 'card') {
      final n = section['n'];
      final label = section['label']?.toString() ?? '';
      if (n != null) return 'ใบที่ $n${label.isEmpty ? '' : ' · $label'}';
    }
    return t;
  }

  static Color _verdictColor(String r) {
    if (r.startsWith('ยังไม่')) return const Color(0xFFFFB86B);
    if (r.startsWith('ไม่')) return const Color(0xFFFF8FA0);
    if (r.startsWith('ใช่') || r.contains('เลือกทางเลือก')) return JuntraColors.mintGreen;
    return JuntraColors.goldLight;
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.section});
  final Map<String, dynamic> section;

  @override
  Widget build(BuildContext context) {
    final tone = section['tone']?.toString() ?? 'neutral';
    final color = switch (tone) {
      'good' => JuntraColors.mintGreen,
      'caution' => const Color(0xFFFFB86B),
      _ => JuntraColors.purpleBright,
    };
    final theme = section['theme']?.toString();
    final body = section['body']?.toString().trim() ?? '';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(section['month']?.toString() ?? '', style: baiJamjuree(size: 14, color: JuntraColors.textCream))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(section['tone_label']?.toString() ?? '', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (theme != null && theme.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(theme, style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w600)),
          ],
          if (body.isNotEmpty) ...[
            const SizedBox(height: 4),
            MarkdownBody(data: body, selectable: true, styleSheet: _md()),
          ],
        ],
      ),
    );
  }
}

MarkdownStyleSheet _md() => MarkdownStyleSheet(
      p: const TextStyle(fontSize: 13.5, color: JuntraColors.textLavender, height: 1.65),
      strong: const TextStyle(fontWeight: FontWeight.w700, color: JuntraColors.textCream),
      listBullet: const TextStyle(fontSize: 13.5, color: JuntraColors.textLavender, height: 1.65),
      h3: baiJamjuree(size: 14, color: JuntraColors.gold),
      tableBody: const TextStyle(fontSize: 12.5, color: JuntraColors.textLavender),
      tableHead: const TextStyle(fontSize: 12.5, color: JuntraColors.gold, fontWeight: FontWeight.w700),
      tableBorder: TableBorder.all(color: JuntraColors.purple.withValues(alpha: 0.35)),
    );
