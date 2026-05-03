import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// "POWERED BY XMAN STUDIO" — appears at the bottom of splash + as
/// a subtle global footer per the handoff (§11 Brand Assets).
class XmanStudioFooter extends StatelessWidget {
  const XmanStudioFooter({super.key, this.showVersion = false});
  final bool showVersion;

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: const TextStyle(
        fontSize: 9, color: JuntraColors.textFaint,
        letterSpacing: 3.6, fontWeight: FontWeight.w500,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('POWERED BY '),
          Text(
            'XMAN STUDIO',
            style: TextStyle(
              fontSize: 10,
              color: JuntraColors.gold,
              letterSpacing: 4.0,
              fontWeight: FontWeight.w700,
              shadows: [
                Shadow(color: JuntraColors.gold.withValues(alpha: 0.5), blurRadius: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
