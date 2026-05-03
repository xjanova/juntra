import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Birth data — same shape as the React handoff's BirthData struct.
class BirthData {
  const BirthData({
    required this.year, required this.month, required this.day,
    required this.hour, required this.minute,
    required this.lat, required this.lng,
    required this.placeName, required this.tzOffsetHours,
  });
  final int year, month, day;
  final int hour, minute;
  final double lat, lng;
  final String placeName;
  final double tzOffsetHours;
}

class ZodiacSign {
  const ZodiacSign({
    required this.idx, required this.en, required this.th,
    required this.symbol, required this.element, required this.elementTh,
  });
  final int idx;       // 0..11 (Aries..Pisces)
  final String en;
  final String th;
  final String symbol;
  final String element; // fire/earth/air/water
  final String elementTh;
}

const _signs = <ZodiacSign>[
  ZodiacSign(idx: 0, en: 'Aries', th: 'เมษ', symbol: '♈', element: 'fire', elementTh: 'ธาตุไฟ'),
  ZodiacSign(idx: 1, en: 'Taurus', th: 'พฤษภ', symbol: '♉', element: 'earth', elementTh: 'ธาตุดิน'),
  ZodiacSign(idx: 2, en: 'Gemini', th: 'เมถุน', symbol: '♊', element: 'air', elementTh: 'ธาตุลม'),
  ZodiacSign(idx: 3, en: 'Cancer', th: 'กรกฎ', symbol: '♋', element: 'water', elementTh: 'ธาตุน้ำ'),
  ZodiacSign(idx: 4, en: 'Leo', th: 'สิงห์', symbol: '♌', element: 'fire', elementTh: 'ธาตุไฟ'),
  ZodiacSign(idx: 5, en: 'Virgo', th: 'กันย์', symbol: '♍', element: 'earth', elementTh: 'ธาตุดิน'),
  ZodiacSign(idx: 6, en: 'Libra', th: 'ตุล', symbol: '♎', element: 'air', elementTh: 'ธาตุลม'),
  ZodiacSign(idx: 7, en: 'Scorpio', th: 'พิจิก', symbol: '♏', element: 'water', elementTh: 'ธาตุน้ำ'),
  ZodiacSign(idx: 8, en: 'Sagittarius', th: 'ธนู', symbol: '♐', element: 'fire', elementTh: 'ธาตุไฟ'),
  ZodiacSign(idx: 9, en: 'Capricorn', th: 'มังกร', symbol: '♑', element: 'earth', elementTh: 'ธาตุดิน'),
  ZodiacSign(idx: 10, en: 'Aquarius', th: 'กุมภ์', symbol: '♒', element: 'air', elementTh: 'ธาตุลม'),
  ZodiacSign(idx: 11, en: 'Pisces', th: 'มีน', symbol: '♓', element: 'water', elementTh: 'ธาตุน้ำ'),
];

class NatalPosition {
  const NatalPosition({
    required this.lon, required this.signIdx,
    required this.signEn, required this.signTh, required this.signSymbol,
    required this.element, required this.elementTh,
    this.glyph = '', this.labelTh = '', this.color = JuntraColors.gold,
  });
  final double lon;
  final int signIdx;
  final String signEn, signTh, signSymbol;
  final String element, elementTh;
  final String glyph;
  final String labelTh;
  final Color color;
}

class NatalAspect {
  const NatalAspect({required this.fromLon, required this.toLon, required this.kind});
  final double fromLon;
  final double toLon;
  final String kind; // conj/sextile/square/trine/opposition
}

/// A natal chart computed from [BirthData].
///
/// **Accuracy note:** Sun and Moon longitudes use the simplified Meeus
/// formulas (±1° accuracy — fine for popular astrology). Other planets
/// use deterministic offsets keyed off Sun longitude — these are
/// **placeholders** until the server endpoint `/v1/natal/compute`
/// (Swiss Ephemeris) replaces them in production.
class NatalChart {
  NatalChart._({
    required this.birth, required this.sun, required this.moon,
    required this.ascendant, required this.planets, required this.aspectsTo,
  });

  final BirthData birth;
  final NatalPosition sun;
  final NatalPosition moon;
  final NatalPosition ascendant;
  final List<NatalPosition> planets;
  final List<NatalAspect> aspectsTo;

  factory NatalChart.compute(BirthData b) {
    final jd = _julianDay(b.year, b.month, b.day, b.hour, b.minute,
        b.tzOffsetHours);
    final t = (jd - 2451545.0) / 36525.0;

    final sunLon = _sunLongitude(t);
    final moonLon = _moonLongitude(t);

    // Approximate ASC: rough hour angle calc — good enough as placeholder
    // until /v1/natal/compute replaces with real value from Swiss Eph.
    final lst = _localSiderealTime(jd, b.lng);
    final ascLon = (lst * 15 + b.lat * 0.5) % 360;

    NatalPosition pos(double lon, {String glyph = '', String label = '', Color color = JuntraColors.gold}) {
      final n = lon % 360;
      final idx = (n / 30).floor() % 12;
      final s = _signs[idx];
      return NatalPosition(
        lon: n, signIdx: idx,
        signEn: s.en, signTh: s.th, signSymbol: s.symbol,
        element: s.element, elementTh: s.elementTh,
        glyph: glyph, labelTh: label, color: color,
      );
    }

    final sun = pos(sunLon, glyph: '☉', label: 'อาทิตย์', color: const Color(0xFFFFD740));
    final moon = pos(moonLon, glyph: '☽', label: 'จันทร์', color: const Color(0xFFE0E0E0));
    final asc = pos(ascLon, glyph: 'ASC', label: 'ลัคนา', color: JuntraColors.cyan);

    // Placeholder planets — keyed off sun lon for stable demo output
    final planets = <NatalPosition>[
      sun,
      moon,
      pos((sunLon + 25) % 360, glyph: '☿', label: 'พุธ', color: const Color(0xFFA1887F)),
      pos((sunLon - 35 + 360) % 360, glyph: '♀', label: 'ศุกร์', color: const Color(0xFFF06292)),
      pos((sunLon + 110) % 360, glyph: '♂', label: 'อังคาร', color: const Color(0xFFFF6B47)),
      pos((sunLon + 200) % 360, glyph: '♃', label: 'พฤหัส', color: const Color(0xFFFFB300)),
      pos((sunLon + 250) % 360, glyph: '♄', label: 'เสาร์', color: const Color(0xFF9E9E9E)),
    ];

    // A few illustrative aspects (between sun↔moon, sun↔jupiter, etc.)
    final aspects = <NatalAspect>[
      NatalAspect(fromLon: sun.lon, toLon: moon.lon, kind: 'conj'),
      NatalAspect(fromLon: sun.lon, toLon: planets[5].lon, kind: 'trine'),
      NatalAspect(fromLon: moon.lon, toLon: planets[3].lon, kind: 'sextile'),
      NatalAspect(fromLon: planets[4].lon, toLon: planets[6].lon, kind: 'square'),
    ];

    return NatalChart._(
      birth: b, sun: sun, moon: moon, ascendant: asc,
      planets: planets, aspectsTo: aspects,
    );
  }

  // ─── Meeus simplified formulas ─────────────────────────────

  static double _julianDay(int y, int m, int d, int hh, int mm, double tz) {
    var year = y, month = m;
    if (month <= 2) { year -= 1; month += 12; }
    final a = (year / 100).floor();
    final b = 2 - a + (a / 4).floor();
    final dayFrac = d + (hh - tz + mm / 60.0) / 24.0;
    return (365.25 * (year + 4716)).floor()
        + (30.6001 * (month + 1)).floor()
        + dayFrac + b - 1524.5;
  }

  static double _sunLongitude(double t) {
    final l0 = 280.46646 + 36000.76983 * t + 0.0003032 * t * t;
    final m = 357.52911 + 35999.05029 * t - 0.0001537 * t * t;
    final mr = m * math.pi / 180;
    final c = (1.914602 - 0.004817 * t) * math.sin(mr)
        + (0.019993 - 0.000101 * t) * math.sin(2 * mr)
        + 0.000289 * math.sin(3 * mr);
    return (l0 + c) % 360;
  }

  static double _moonLongitude(double t) {
    final lp = 218.3164477 + 481267.88123421 * t;
    final d = 297.8501921 + 445267.1114034 * t;
    final m = 357.5291092 + 35999.0502909 * t;
    final mp = 134.9633964 + 477198.8675055 * t;
    final f = 93.2720950 + 483202.0175233 * t;

    double s(double x) => math.sin(x * math.pi / 180);
    final lon = lp
        + 6.289 * s(mp)
        - 1.274 * s(mp - 2 * d)
        + 0.658 * s(2 * d)
        - 0.214 * s(2 * mp)
        - 0.186 * s(m)
        - 0.114 * s(2 * f);
    return ((lon % 360) + 360) % 360;
  }

  static double _localSiderealTime(double jd, double lng) {
    final t = (jd - 2451545.0) / 36525.0;
    final gmst = 280.46061837 + 360.98564736629 * (jd - 2451545.0)
        + 0.000387933 * t * t - t * t * t / 38710000.0;
    return ((gmst + lng) % 360) / 15.0;
  }
}
