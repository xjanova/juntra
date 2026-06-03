import 'package:flutter/material.dart';

/// Brand logo — uses `assets/images/logo-chantra.png` (gold crescent + Thai
/// wordmark, all-in-one). Same `ChantraLogoSize` enum as before so existing
/// callers (splash screen) work unchanged.
class ChantraLogo extends StatelessWidget {
  const ChantraLogo({super.key, this.size = ChantraLogoSize.md});
  final ChantraLogoSize size;

  @override
  Widget build(BuildContext context) {
    final dim = _sizes[size]!;
    return Image.asset(
      'assets/images/logo-chantra.png',
      width: dim,
      height: dim,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, _, _) => SizedBox(
        width: dim, height: dim,
        child: const Center(child: Text('☾', style: TextStyle(fontSize: 48))),
      ),
    );
  }

  static const _sizes = {
    ChantraLogoSize.sm: 80.0,
    ChantraLogoSize.md: 140.0,
    ChantraLogoSize.lg: 220.0,
    ChantraLogoSize.xl: 320.0,
  };
}

enum ChantraLogoSize { sm, md, lg, xl }
