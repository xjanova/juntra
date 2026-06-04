import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/astronomy/birth_data_store.dart';
import '../../core/astronomy/natal_chart.dart';
import '../../shared/widgets/starry_background.dart';
import 'birth_data_editor.dart';

/// Screen 10 — Natal Chart. Beautiful astrology wheel computed from
/// the user's birth data. Three tabs: ผังดวง / ดาวพระเคราะห์ / คำพยากรณ์.
class NatalScreen extends ConsumerStatefulWidget {
  const NatalScreen({super.key});
  @override
  ConsumerState<NatalScreen> createState() => _NatalScreenState();
}

class _NatalScreenState extends ConsumerState<NatalScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    // Birth data comes from the local store — the demo default until the user
    // saves their own — and the chart is recomputed whenever it changes.
    final birth = ref.watch(birthDataProvider);
    final chart = NatalChart.compute(birth.data);

    return Scaffold(
      body: Stack(
        children: [
          const StarryBackground(density: 50, intensity: 0.7),
          SafeArea(
            child: Column(
              children: [
                _Header(
                  subtitle: birth.isCustom
                      ? '${birth.data.placeName} · ${birth.data.day}/${birth.data.month}/${birth.data.year}'
                      : 'ข้อมูลตัวอย่าง · แตะ ✎ เพื่อใส่วันเกิดของลูก',
                  onEdit: () => showBirthDataEditor(context, birth.data),
                ),
                _TabRow(current: _tab, onTap: (i) => setState(() => _tab = i)),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: switch (_tab) {
                      0 => _ChartView(chart: chart),
                      1 => _PlanetsView(chart: chart),
                      _ => _ReadingView(chart: chart),
                    },
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
  const _Header({required this.subtitle, required this.onEdit});
  final String subtitle;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 16, 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: JuntraColors.gold, size: 28),
            onPressed: () => context.canPop() ? context.pop() : context.go(Routes.profile),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ผังดวงดาวเจ้าชะตา', style: baiJamjuree(size: 18)),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5, color: JuntraColors.textMuted,
                    )),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: JuntraColors.purpleBright),
            tooltip: 'แก้ไขข้อมูลวันเกิด',
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}

class _TabRow extends StatelessWidget {
  const _TabRow({required this.current, required this.onTap});
  final int current;
  final ValueChanged<int> onTap;
  @override
  Widget build(BuildContext context) {
    const tabs = ['ผังดวง', 'ดาวพระเคราะห์', 'คำพยากรณ์'];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: tabs.asMap().entries.map((e) {
          final selected = current == e.key;
          return Expanded(
            child: InkWell(
              onTap: () => onTap(e.key),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  gradient: selected ? JuntraColors.goldButtonGradient : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(e.value, style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600,
                  color: selected ? JuntraColors.bgPurpleDeep : JuntraColors.textLavender,
                )),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ChartView extends StatelessWidget {
  const _ChartView({required this.chart});
  final NatalChart chart;
  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('c'),
      padding: const EdgeInsets.all(16),
      children: [
        AspectRatio(
          aspectRatio: 1.0,
          child: CustomPaint(painter: _NatalWheelPainter(chart: chart)),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _Big3Tile(label: 'อาทิตย์', sign: chart.sun.signTh, glyph: '☉')),
            const SizedBox(width: 8),
            Expanded(child: _Big3Tile(label: 'จันทร์', sign: chart.moon.signTh, glyph: '☽')),
            const SizedBox(width: 8),
            Expanded(child: _Big3Tile(label: 'ลัคนา', sign: chart.ascendant.signTh, glyph: 'ASC')),
          ],
        ),
      ],
    );
  }
}

class _Big3Tile extends StatelessWidget {
  const _Big3Tile({required this.label, required this.sign, required this.glyph});
  final String label;
  final String sign;
  final String glyph;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(glyph, style: const TextStyle(
            fontSize: 22, color: JuntraColors.gold,
          )),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(
            fontSize: 11, color: JuntraColors.textMuted,
          )),
          const SizedBox(height: 2),
          Text(sign, style: baiJamjuree(size: 14, color: JuntraColors.textCream)),
        ],
      ),
    );
  }
}

class _NatalWheelPainter extends CustomPainter {
  _NatalWheelPainter({required this.chart});
  final NatalChart chart;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final maxR = math.min(size.width, size.height) / 2 - 4;

    // Outer disc
    canvas.drawCircle(
      Offset(cx, cy), maxR,
      Paint()..shader = const RadialGradient(
        colors: [Color(0xFF1F0F4A), Color(0xFF05010F)],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: maxR)),
    );

    // Zodiac band (R 0.85..0.95) — 12 sectors
    const zodiacColors = [
      JuntraColors.elFire, JuntraColors.elEarth,
      JuntraColors.elAir, JuntraColors.elWater,
    ];
    for (var i = 0; i < 12; i++) {
      final start = -math.pi / 2 + i * (math.pi / 6);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = maxR * 0.10
        ..color = zodiacColors[i % 4].withValues(alpha: 0.55);
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: maxR * 0.90),
        start, math.pi / 6, false, paint,
      );
    }

    // House ring (R 0.55..0.78) — 12 dividers from ASC
    final ascRad = -math.pi / 2 + (chart.ascendant.lon - 90) * math.pi / 180;
    for (var i = 0; i < 12; i++) {
      final ang = ascRad + i * (math.pi / 6);
      final p1 = Offset(cx + math.cos(ang) * maxR * 0.55, cy + math.sin(ang) * maxR * 0.55);
      final p2 = Offset(cx + math.cos(ang) * maxR * 0.78, cy + math.sin(ang) * maxR * 0.78);
      canvas.drawLine(p1, p2, Paint()
        ..color = JuntraColors.gold.withValues(alpha: 0.3)
        ..strokeWidth = 0.8);
    }

    // Aspect lines (faint, illustrative)
    final aspectPaint = Paint()
      ..color = JuntraColors.cyan.withValues(alpha: 0.4)
      ..strokeWidth = 0.6;
    for (var i = 0; i < chart.aspectsTo.length && i < 5; i++) {
      final a = chart.aspectsTo[i];
      final r = maxR * 0.5;
      final ang1 = -math.pi / 2 + a.fromLon * math.pi / 180;
      final ang2 = -math.pi / 2 + a.toLon * math.pi / 180;
      canvas.drawLine(
        Offset(cx + math.cos(ang1) * r, cy + math.sin(ang1) * r),
        Offset(cx + math.cos(ang2) * r, cy + math.sin(ang2) * r),
        aspectPaint,
      );
    }

    // Planets at R 0.65
    for (final p in chart.planets) {
      final ang = -math.pi / 2 + p.lon * math.pi / 180;
      final pos = Offset(cx + math.cos(ang) * maxR * 0.65, cy + math.sin(ang) * maxR * 0.65);
      canvas.drawCircle(pos, 12, Paint()..color = JuntraColors.bgPurpleDeep);
      canvas.drawCircle(pos, 11, Paint()
        ..style = PaintingStyle.stroke
        ..color = p.color.withValues(alpha: 0.8)
        ..strokeWidth = 1.4);
      final tp = TextPainter(
        text: TextSpan(text: p.glyph, style: TextStyle(
          color: p.color, fontSize: 14, fontWeight: FontWeight.w600,
        )),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }

    // Center crescent
    canvas.drawCircle(Offset(cx, cy), maxR * 0.32, Paint()
      ..shader = RadialGradient(colors: [
        JuntraColors.gold.withValues(alpha: 0.3),
        JuntraColors.gold.withValues(alpha: 0),
      ]).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: maxR * 0.32)));
    final natalText = TextPainter(
      text: TextSpan(text: 'NATAL', style: GoogleFonts.cinzel(
        textStyle: const TextStyle(
          color: JuntraColors.gold, fontSize: 12, letterSpacing: 3,
          fontWeight: FontWeight.w700,
        ),
      )),
      textDirection: TextDirection.ltr,
    )..layout();
    natalText.paint(canvas, Offset(cx - natalText.width / 2, cy - 6));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

class _PlanetsView extends StatelessWidget {
  const _PlanetsView({required this.chart});
  final NatalChart chart;
  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: const ValueKey('p'),
      padding: const EdgeInsets.all(16),
      itemCount: chart.planets.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final p = chart.planets[i];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(JuntraRadius.card),
            border: Border.all(color: p.color.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.color.withValues(alpha: 0.18),
                ),
                alignment: Alignment.center,
                child: Text(p.glyph, style: TextStyle(
                  fontSize: 20, color: p.color,
                )),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.labelTh, style: baiJamjuree(size: 14)),
                    Text('ราศี${p.signTh} ${p.degInSign.toStringAsFixed(1)}°',
                        style: const TextStyle(
                          fontSize: 11, color: JuntraColors.textMuted,
                        )),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ReadingView extends StatelessWidget {
  const _ReadingView({required this.chart});
  final NatalChart chart;
  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const ValueKey('r'),
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: JuntraColors.mysticHeroGradient,
            borderRadius: BorderRadius.circular(JuntraRadius.hero),
            border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('คำพยากรณ์เจ้าชะตา', style: baiJamjuree(size: 18)),
              const SizedBox(height: 8),
              Text(
                'อาทิตย์${chart.sun.signTh} ผสานกับจันทร์${chart.moon.signTh} '
                'และลัคนา${chart.ascendant.signTh} — ลูกเกิดมาพร้อมพลังของ '
                '${chart.sun.elementTh} ที่ผสานความอ่อนโยนของ${chart.moon.elementTh} '
                'นี่คือเสน่ห์ที่ทำให้คนรอบข้างหลงใหลโดยไม่รู้ตัว',
                style: const TextStyle(
                  fontSize: 13, color: JuntraColors.textLavender, height: 1.7,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
