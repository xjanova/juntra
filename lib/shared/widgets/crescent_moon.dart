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
