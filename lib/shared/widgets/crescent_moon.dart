import 'package:flutter/material.dart';

/// Gold gradient crescent — used as the brand glyph and the centerpiece
/// of the natal chart's inner core.
class CrescentMoon extends StatelessWidget {
  const CrescentMoon({super.key, this.size = 48});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _CrescentPainter()),
    );
  }
}

/// ดวงจันทร์ตามดิถีจริงของวันนั้น — วาดจากค่าส่องสว่างที่เซิร์ฟเวอร์คำนวณ
///
/// พอร์ตสูตรมาจาก `resources/views/components/moon-phase.blade.php` ของเว็บ
/// ตรง ๆ เพื่อให้เสี้ยวบนแอพกับบนเว็บเป็นรูปเดียวกันเป๊ะในวันเดียวกัน:
/// จานมืดเต็มดวง แล้วครอบส่วนสว่างด้วยขอบนอกครึ่งวงกลม (คงที่) + ขอบในที่เป็น
/// วงรีซึ่งความกว้างแปรตามค่าส่องสว่าง จึงได้เสี้ยวจริงตั้งแต่จันทร์ดับจนเพ็ญ
///
/// [illumination] 0.0–1.0 · [waxing] true = ข้างขึ้น (สว่างอยู่ขวา)
class MoonPhaseGlyph extends StatelessWidget {
  const MoonPhaseGlyph({
    super.key,
    required this.illumination,
    required this.waxing,
    this.size = 32,
  });

  final double illumination;
  final bool waxing;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _MoonPhasePainter(
          illumination: illumination.clamp(0.0, 1.0),
          waxing: waxing,
        ),
      ),
    );
  }
}

class _MoonPhasePainter extends CustomPainter {
  _MoonPhasePainter({required this.illumination, required this.waxing});
  final double illumination;
  final bool waxing;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);

    // จานมืด + ขอบทองบาง ๆ — เห็นขอบดวงแม้ตอนจันทร์ดับ
    canvas.drawCircle(c, r * 0.94, Paint()..color = const Color(0x14FFFFFF));
    canvas.drawCircle(
      c,
      r * 0.94,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.06
        ..color = const Color(0x59F0C75E),
    );

    if (illumination <= 0.005) return;

    final rr = r * 0.94;
    // ครึ่งความกว้างของ terminator: 0 = ครึ่งดวงพอดี, rr = ขอบตรงข้าม
    final k = (2 * illumination - 1).abs() * rr;
    final sweepOuter = waxing;
    final sweepInner = illumination > 0.5 ? sweepOuter : !sweepOuter;

    final top = Offset(c.dx, c.dy - rr);
    final bottom = Offset(c.dx, c.dy + rr);

    final path = Path()..moveTo(top.dx, top.dy);
    path.arcToPoint(bottom,
        radius: Radius.circular(rr), largeArc: false, clockwise: sweepOuter);
    if (k < 0.5) {
      // ครึ่งดวงพอดี — ขอบในเป็นเส้นตรง (rx = 0 วาดเป็นวงรีไม่ได้)
      path.lineTo(top.dx, top.dy);
    } else {
      path.arcToPoint(top,
          radius: Radius.elliptical(k, rr), largeArc: false, clockwise: sweepInner);
    }
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.24, -0.32),
          colors: [Color(0xFFFFFDF3), Color(0xFFF2E6C4), Color(0xFFD8C48D)],
          stops: [0.0, 0.7, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: rr)),
    );
  }

  @override
  bool shouldRepaint(covariant _MoonPhasePainter old) =>
      old.illumination != illumination || old.waxing != waxing;
}

class _CrescentPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);

    // Crescent = large gradient disc minus offset cut-out (even-odd fill).
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [
          Color(0xFFFFE7A0), Color(0xFFF0C75E),
          Color(0xFFC99B2D), Color(0xFF7A5A1E),
        ],
        stops: [0.0, 0.4, 0.7, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: r));

    final path = Path()
      ..addOval(Rect.fromCircle(center: c, radius: r * 0.85))
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(
        center: Offset(c.dx + r * 0.22, c.dy - r * 0.10),
        radius: r * 0.78,
      ));
    canvas.drawPath(path, paint);

    // Tiny gold accent star to the upper-left
    final accent = Paint()..color = const Color(0xCCF0C75E);
    canvas.drawCircle(Offset(c.dx - r * 0.12, c.dy - r * 0.55), r * 0.04, accent);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
