import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens — the website's live theme `juntra-payakorn`
/// (juntraweb `resources/css/themes/juntra-payakorn.css`, 2026-11).
///
/// The app follows the web: owner asked for "สีและฟอนต์ให้ตรงกับธีมที่เว็บเปิดใช้อยู่".
/// Token names are kept from the old handoff palette so every screen picks the
/// new values up without edits; the comment on each line names the web variable.
class JuntraColors {
  JuntraColors._();

  // Backgrounds (--bg-0 / --bg-1 / --bg-2 and two lifts for cards)
  static const bgDeepest = Color(0xFF0A0612);    // --bg-0
  static const bgDark1 = Color(0xFF100722);      // body gradient middle
  static const bgDark2 = Color(0xFF160A26);      // --bg-1
  static const bgPurpleDeep = Color(0xFF241038); // --bg-2 (cards, sheets)
  static const bgPurple = Color(0xFF34195A);
  static const bgPurpleLight = Color(0xFF4A2A7A);

  // Gold (--gold-2 / --gold / --gold-3)
  static const goldLight = Color(0xFFF6E3A8); // --gold-2
  static const gold = Color(0xFFE7C97A);      // --gold
  static const goldMid = Color(0xFFC8A762);
  static const goldDark = Color(0xFFA8854A);  // --gold-3

  // Violet / magenta (--violet-2 / --violet / --magenta)
  static const purpleBright = Color(0xFFB07AFF); // --violet-2
  static const purple = Color(0xFF7A3DF0);       // --violet
  static const purpleDeep = Color(0xFF5B2BC4);
  static const magenta = Color(0xFFD24AD1);      // --magenta
  static const rose = Color(0xFFFF8FD4);         // --rose
  static const moon = Color(0xFFFFF7E0);         // --moon

  // Oracle rooms (config/chat_rooms.php accent)
  static const roomBusaba = Color(0xFF7CC7F6);
  static const roomMaemor = Color(0xFFA884F4);
  static const roomKunsai = Color(0xFFE0455F);

  // Mystic accents
  static const cyan = Color(0xFF7FFFD4);      // ASC marker, water planets
  static const mintGreen = Color(0xFF3DDC97); // online indicator

  // Astrology element colors
  static const elFire = Color(0xFFFF6B47);
  static const elEarth = Color(0xFF8BC34A);
  static const elAir = Color(0xFFFFEE58);
  static const elWater = Color(0xFF42A5F5);

  // Text ramp (--ink / --ink-dim / --ink-mute)
  static const textPrimary = Color(0xFFF3E9FF);  // --ink
  static const textCream = Color(0xFFF6E3A8);    // headlines (--gold-2)
  static const textLavender = Color(0xFFC8B8DE); // body (--ink-dim)
  static const textMuted = Color(0xFFA696C4);
  static const textDim = Color(0xFF8A7AA8);      // --ink-mute
  static const textFaint = Color(0xFF6A5A88);

  // Lines (--line / --line-soft)
  static const line = Color(0x47E7C97A);
  static const lineSoft = Color(0x21E7C97A);

  // Gradients
  /// `.btn-primary`: #f6e3a8 → #e7c97a → #a8854a
  static const goldButtonGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF6E3A8), Color(0xFFE7C97A), Color(0xFFA8854A)],
    stops: [0.0, 0.5, 1.0],
  );

  /// `.service` card: rgba(36,16,56,.55) → rgba(15,8,28,.55)
  static const purpleCardGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x8C241038), Color(0x8C0F081C)],
  );

  static const mysticHeroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x407A3DF0), Color(0x1AE7C97A)],
  );

  /// Headline text fill (`.section-title`): #fff7e0 → #e7c97a
  static const headlineGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFF7E0), Color(0xFFE7C97A)],
  );

  /// Page background (`.bg-fixed`): violet glow top-left, magenta right, gold low.
  static const nightSky = RadialGradient(
    center: Alignment(-0.6, -0.8),
    radius: 1.4,
    colors: [Color(0xFF2A1352), Color(0xFF100722), Color(0xFF0A0612)],
    stops: [0.0, 0.55, 1.0],
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

/// Border radii — the web rounds cards to 20-22 px and pills to 999.
class JuntraRadius {
  JuntraRadius._();
  static const chip = 999.0;
  static const input = 14.0;
  static const card = 20.0;
  static const hero = 24.0;
}

/// Standard shadows / glows
class JuntraShadows {
  JuntraShadows._();
  static const goldGlow = [
    BoxShadow(color: Color(0x66E7C97A), blurRadius: 18, spreadRadius: -4, offset: Offset(0, 8)),
  ];
  static const goldStrong = [
    BoxShadow(color: Color(0x80E7C97A), blurRadius: 28, spreadRadius: -6, offset: Offset(0, 12)),
  ];
  static const cardDeep = [
    BoxShadow(color: Color(0x99000000), blurRadius: 30, spreadRadius: -10, offset: Offset(0, 16)),
  ];
}

class JuntraTheme {
  JuntraTheme._();

  static ThemeData dark() {
    // Body = Bai Jamjuree (--font-thai) · headlines = Charm (--font-thai-display)
    final baseTextTheme = GoogleFonts.baiJamjureeTextTheme(
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
        onPrimary: Color(0xFF1A0E2E),
        onSecondary: JuntraColors.bgDeepest,
        onSurface: JuntraColors.textPrimary,
        error: Color(0xFFFF6B6B),
      ),
      // SnackBar ของ M3 ใช้สีตัวอักษร onInverseSurface ซึ่ง ColorScheme.dark ตั้งเป็น
      // surface (ม่วงเข้ม) — ตรงกับพื้น bgPurpleDeep ที่ทุกจุดใช้ ข้อความจึงหายทั้งแอพ
      // ("เติมเครดิตสำเร็จ", "เปลี่ยนรหัสผ่านแล้ว" ขึ้นเป็นกล่องว่าง) → กำหนดสีที่อ่านได้ไว้ที่นี่
      snackBarTheme: SnackBarThemeData(
        backgroundColor: JuntraColors.bgPurpleDeep,
        contentTextStyle: GoogleFonts.baiJamjuree(
          textStyle: const TextStyle(
            fontSize: 14, color: JuntraColors.textCream, height: 1.4,
          ),
        ),
        actionTextColor: JuntraColors.gold,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: JuntraColors.line, width: 0.6),
        ),
      ),
      textTheme: baseTextTheme.copyWith(
        displayLarge: charm(size: 34),
        displayMedium: charm(size: 26),
        displaySmall: charm(size: 22),
        headlineMedium: charm(size: 20, color: JuntraColors.goldLight),
        titleMedium: GoogleFonts.baiJamjuree(
          textStyle: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600,
            color: JuntraColors.textPrimary,
          ),
        ),
        bodyMedium: GoogleFonts.baiJamjuree(
          textStyle: const TextStyle(
            fontSize: 13.5, fontWeight: FontWeight.w400,
            color: JuntraColors.textLavender, height: 1.6,
          ),
        ),
        bodySmall: GoogleFonts.baiJamjuree(
          textStyle: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w400,
            color: JuntraColors.textMuted, height: 1.55,
          ),
        ),
        labelMedium: GoogleFonts.baiJamjuree(
          textStyle: const TextStyle(
            fontSize: 10.5, fontWeight: FontWeight.w500,
            color: JuntraColors.textDim, letterSpacing: 1.2,
          ),
        ),
      ),
      iconTheme: const IconThemeData(color: JuntraColors.gold),
      dividerTheme: const DividerThemeData(
        color: JuntraColors.lineSoft,
        thickness: 0.6,
      ),
      cardTheme: CardThemeData(
        color: JuntraColors.bgPurpleDeep,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(JuntraRadius.card),
          side: const BorderSide(color: JuntraColors.lineSoft),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: JuntraColors.bgDark2,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          side: BorderSide(color: JuntraColors.line, width: 0.6),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: JuntraColors.bgDark2,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: JuntraColors.line, width: 0.6),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0x590A0612),
        hintStyle: const TextStyle(color: JuntraColors.textDim),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(JuntraRadius.input),
          borderSide: const BorderSide(color: JuntraColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(JuntraRadius.input),
          borderSide: const BorderSide(color: JuntraColors.lineSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(JuntraRadius.input),
          borderSide: const BorderSide(color: JuntraColors.gold, width: 1.2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: JuntraColors.gold,
          foregroundColor: const Color(0xFF1A0E2E),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.baiJamjuree(
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: JuntraColors.goldLight,
          side: const BorderSide(color: JuntraColors.line),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: JuntraColors.goldLight),
      ),
    );
  }
}

/// Latin display serif — the web's `--font-display` (Cormorant Garamond,
/// italic small caps feel). Kept under the old name so callers ("NATAL",
/// card names, house numbers) did not have to change when Cinzel left.
TextStyle cinzel({double size = 12, FontWeight weight = FontWeight.w600, Color? color}) {
  return GoogleFonts.cormorantGaramond(
    textStyle: TextStyle(
      fontSize: size * 1.12, fontWeight: weight,
      fontStyle: FontStyle.italic,
      color: color ?? JuntraColors.gold,
      letterSpacing: size * 0.18,
    ),
  );
}

/// Thai display — the web's `--font-thai-display` (Charm). Headlines,
/// section titles, room and package names.
TextStyle charm({double size = 22, FontWeight weight = FontWeight.w700, Color? color}) {
  return GoogleFonts.charm(
    textStyle: TextStyle(
      fontSize: size,
      // Charm ships 400 + 700 only.
      fontWeight: weight.value >= 600 ? FontWeight.w700 : FontWeight.w400,
      color: color ?? JuntraColors.textCream,
      height: 1.3,
    ),
  );
}

/// Thai heading helper used across the app.
///
/// Like the web: headline sizes (≥ 18 px) use Charm (`--font-thai-display`);
/// smaller labels stay in Bai Jamjuree (`--font-thai`), because Charm's thin
/// calligraphic strokes stop reading well below that size on a phone.
TextStyle baiJamjuree({double size = 18, FontWeight weight = FontWeight.w700, Color? color}) {
  if (size >= 18) return charm(size: size + 1, weight: weight, color: color);
  return GoogleFonts.baiJamjuree(
    textStyle: TextStyle(
      fontSize: size, fontWeight: weight,
      color: color ?? JuntraColors.textCream,
      height: 1.25,
    ),
  );
}
