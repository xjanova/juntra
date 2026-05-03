import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme.dart';
import 'crescent_moon.dart';

/// Brand logo: gold crescent + "จันทรา / พยากรณ์" stacked Bai Jamjuree
/// wordmark + small all-caps eyebrow.
class ChantraLogo extends StatelessWidget {
  const ChantraLogo({super.key, this.size = ChantraLogoSize.md});
  final ChantraLogoSize size;

  @override
  Widget build(BuildContext context) {
    final s = _sizes[size]!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CrescentMoon(size: s.moon),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ShaderMask(
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Color(0xFFFFE7A0), Color(0xFFF0C75E), Color(0xFFB8881F)],
                stops: [0.0, 0.5, 1.0],
              ).createShader(rect),
              child: Text(
                'จันทรา',
                style: GoogleFonts.baiJamjuree(
                  textStyle: TextStyle(
                    fontSize: s.title,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                    letterSpacing: 0.4,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'พยากรณ์',
              style: GoogleFonts.baiJamjuree(
                textStyle: TextStyle(
                  fontSize: s.title * 0.7,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                  letterSpacing: 0.6,
                  color: JuntraColors.purpleBright,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'เพจดูดวง',
              style: TextStyle(
                fontSize: s.sub,
                color: JuntraColors.textFaint,
                letterSpacing: s.sub * 0.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static const _sizes = {
    ChantraLogoSize.sm: _S(moon: 32, title: 18, sub: 9),
    ChantraLogoSize.md: _S(moon: 56, title: 28, sub: 12),
    ChantraLogoSize.lg: _S(moon: 96, title: 44, sub: 16),
    ChantraLogoSize.xl: _S(moon: 140, title: 64, sub: 22),
  };
}

enum ChantraLogoSize { sm, md, lg, xl }

class _S {
  const _S({required this.moon, required this.title, required this.sub});
  final double moon;
  final double title;
  final double sub;
}
