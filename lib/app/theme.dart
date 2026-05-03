import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens ported verbatim from the Juntra handoff
/// (`extracted/juntra/project/design_handoff_juntra/README.md` §3).
///
/// The palette is gold-on-deep-purple-on-near-black, with mystic
/// accents (cyan for water-element planets, mint for online status).
class JuntraColors {
  JuntraColors._();

  // Backgrounds
  static const bgDeepest = Color(0xFF000000);
  static const bgDark1 = Color(0xFF060309);
  static const bgDark2 = Color(0xFF0A0414);
  static const bgPurpleDeep = Color(0xFF1A0F2E);
  static const bgPurple = Color(0xFF2D1A5C);
  static const bgPurpleLight = Color(0xFF4A2E7A);

  // Gold (primary brand accent)
  static const goldLight = Color(0xFFFFE7A0);
  static const gold = Color(0xFFF0C75E);
  static const goldMid = Color(0xFFC99B2D);
  static const goldDark = Color(0xFF7A5510);

  // Purple secondaries
  static const purpleBright = Color(0xFFC39BD3);
  static const purple = Color(0xFF9B59B6);
  static const purpleDeep = Color(0xFF7C4DFF);

  // Mystic accents
  static const cyan = Color(0xFF7FFFD4);     // ASC marker, water planets
  static const mintGreen = Color(0xFF00E5A0); // online indicator

  // Astrology element colors
  static const elFire = Color(0xFFFF6B47);
  static const elEarth = Color(0xFF8BC34A);
  static const elAir = Color(0xFFFFEE58);
  static const elWater = Color(0xFF42A5F5);

  // Text ramp
  static const textPrimary = Color(0xFFFFFFFF);
  static const textCream = Color(0xFFFFE7A0);   // hero / serif headlines
  static const textLavender = Color(0xFFD4C5E8); // body
  static const textMuted = Color(0xFFA899C7);    // secondary
  static const textDim = Color(0xFF8B7BA8);      // labels
  static const textFaint = Color(0xFF6B5980);    // eyebrow

  // Convenience gradients
  static const goldButtonGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF4D27A), Color(0xFFD4A537), Color(0xFFA07820)],
    stops: [0.0, 0.5, 1.0],
  );

  static const purpleCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xB22D1A5C), Color(0xB24A2E7A)],
  );

  static const mysticHeroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x339B59B6), Color(0x1AF0C75E)],
  );

  static const nightSky = RadialGradient(
    center: Alignment(0.0, -0.4),
    radius: 1.2,
    colors: [Color(0xFF1A0F2E), Color(0xFF060309), Color(0xFF000000)],
    stops: [0.0, 0.7, 1.0],
  );
}

/// Spacing rhythm: 4 / 6 / 8 / 10 / 12 / 14 / 16 / 20 / 24 / 32 / 40
class JuntraSpacing {
  JuntraSpacing._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const huge = 40.0;
}

/// Border radii from the spec
class JuntraRadius {
  JuntraRadius._();
  static const chip = 10.0;
  static const input = 12.0;
  static const card = 16.0;
  static const hero = 24.0;
}

/// Standard shadows / glows
class JuntraShadows {
  JuntraShadows._();
  static const goldGlow = [
    BoxShadow(color: Color(0x80F0C75E), blurRadius: 12, spreadRadius: 0),
  ];
  static const goldStrong = [
    BoxShadow(color: Color(0xB3F0C75E), blurRadius: 20, spreadRadius: 0),
  ];
  static const cardDeep = [
    BoxShadow(color: Color(0x99000000), blurRadius: 24, offset: Offset(0, 8)),
  ];
}

class JuntraTheme {
  JuntraTheme._();

  static ThemeData dark() {
    final baseTextTheme = GoogleFonts.notoSansThaiTextTheme(
      ThemeData.dark().textTheme,
    );

    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: JuntraColors.bgDeepest,
      colorScheme: const ColorScheme.dark(
        primary: JuntraColors.gold,
        secondary: JuntraColors.purpleBright,
        surface: JuntraColors.bgPurpleDeep,
        onPrimary: JuntraColors.bgPurpleDeep,
        onSecondary: JuntraColors.bgDeepest,
        onSurface: JuntraColors.textPrimary,
        error: Color(0xFFFF6B6B),
      ),
      // Headlines use Bai Jamjuree (Thai display serif). Body keeps
      // Noto Sans Thai (set above via baseTextTheme).
      textTheme: baseTextTheme.copyWith(
        displayLarge: GoogleFonts.baiJamjuree(
          textStyle: const TextStyle(
            fontSize: 32, fontWeight: FontWeight.w700,
            color: JuntraColors.textCream, height: 1.2,
          ),
        ),
        displayMedium: GoogleFonts.baiJamjuree(
          textStyle: const TextStyle(
            fontSize: 24, fontWeight: FontWeight.w700,
            color: JuntraColors.textCream, height: 1.2,
          ),
        ),
        displaySmall: GoogleFonts.baiJamjuree(
          textStyle: const TextStyle(
            fontSize: 22, fontWeight: FontWeight.w700,
            color: JuntraColors.textCream, height: 1.25,
          ),
        ),
        headlineMedium: GoogleFonts.baiJamjuree(
          textStyle: const TextStyle(
            fontSize: 19, fontWeight: FontWeight.w600,
            color: JuntraColors.textPrimary,
          ),
        ),
        titleMedium: const TextStyle(
          fontSize: 14, fontWeight: FontWeight.w600,
          color: JuntraColors.textPrimary,
        ),
        bodyMedium: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w400,
          color: JuntraColors.textLavender, height: 1.5,
        ),
        bodySmall: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w400,
          color: JuntraColors.textMuted, height: 1.5,
        ),
        labelMedium: const TextStyle(
          fontSize: 10, fontWeight: FontWeight.w500,
          color: JuntraColors.textFaint, letterSpacing: 1.6,
        ),
      ),
      iconTheme: const IconThemeData(color: JuntraColors.gold),
      dividerTheme: const DividerThemeData(
        color: Color(0x33D4C5E8),
        thickness: 0.5,
      ),
      cardTheme: CardThemeData(
        color: JuntraColors.bgPurpleDeep,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(JuntraRadius.card),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: JuntraColors.gold,
          foregroundColor: JuntraColors.bgPurpleDeep,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: const TextStyle(
            fontSize: 15, fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Cinzel for English serif headers ("NATAL", house numbers).
TextStyle cinzel({double size = 12, FontWeight weight = FontWeight.w600, Color? color}) {
  return GoogleFonts.cinzel(
    textStyle: TextStyle(
      fontSize: size, fontWeight: weight,
      color: color ?? JuntraColors.gold,
      letterSpacing: size * 0.15,
    ),
  );
}

/// Bai Jamjuree for Thai serif headers
TextStyle baiJamjuree({double size = 18, FontWeight weight = FontWeight.w700, Color? color}) {
  return GoogleFonts.baiJamjuree(
    textStyle: TextStyle(
      fontSize: size, fontWeight: weight,
      color: color ?? JuntraColors.textCream,
      height: 1.2,
    ),
  );
}
