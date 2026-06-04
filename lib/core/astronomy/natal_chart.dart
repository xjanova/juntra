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

  /// Degrees within the current 30° sign (0..29.99) — useful for the
  /// planets list ("ราศีสิงห์ 14°").
  double get degInSign => lon - signIdx * 30;
}

class NatalAspect {
  const NatalAspect({
    required this.fromLon, required this.toLon,
    required this.kind, required this.orb,
  });
  final double fromLon;
  final double toLon;
  final String kind; // conj/sextile/square/trine/opposition
  final double orb;  // how far from exact, in degrees (tighter = stronger)
}

/// A natal chart computed from [BirthData].
///
/// **Accuracy:** all luminary and planetary longitudes are *geocentric
/// ecliptic* and computed on-device from Keplerian elements (Sun via the
/// Meeus solar series; Mercury–Saturn via Schlyter's perturbation-free
/// orbital elements; Moon via the truncated Meeus lunar series). Expect
/// ≈0.1–0.5° on the Sun/Moon and a few arc-minutes to ~1° on the planets
/// over 1900–2100 — comfortably inside a 30°-wide sign, which is all popular
/// astrology needs. Houses use a whole-sign-from-Ascendant scheme.
///
/// When the server ships `/v1/natal/compute` (Swiss Ephemeris) the chart can
/// be sourced from it for arc-second accuracy; until then this is a real,
/// self-contained computation rather than a placeholder.
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
    // Schlyter's day number: days (incl. fraction) since 1999-12-31 00:00 UT.
    final d = jd - 2451543.5;
    final t = (jd - 2451545.0) / 36525.0; // Julian centuries (J2000) for Moon.

    final sunState = _solarState(d);
    final moonLon = _moonLongitude(t);
    final obliquity = 23.4393 - 3.563e-7 * d;
    final ascLon = _ascendant(_localSiderealTime(jd, b.lng) * 15, b.lat, obliquity);

    NatalPosition pos(double lon, {String glyph = '', String label = '', Color color = JuntraColors.gold}) {
      final n = _mod360(lon);
      final idx = (n / 30).floor() % 12;
      final s = _signs[idx];
      return NatalPosition(
        lon: n, signIdx: idx,
        signEn: s.en, signTh: s.th, signSymbol: s.symbol,
        element: s.element, elementTh: s.elementTh,
        glyph: glyph, labelTh: label, color: color,
      );
    }

    final sun = pos(sunState.lon, glyph: '☉', label: 'อาทิตย์', color: const Color(0xFFFFD740));
    final moon = pos(moonLon, glyph: '☽', label: 'จันทร์', color: const Color(0xFFE0E0E0));
    final asc = pos(ascLon, glyph: 'ASC', label: 'ลัคนา', color: JuntraColors.cyan);

    // Real geocentric longitudes for Mercury → Saturn.
    final planets = <NatalPosition>[
      sun,
      moon,
      pos(_geocentricLongitude(_mercury, d, sunState), glyph: '☿', label: 'พุธ', color: const Color(0xFFA1887F)),
      pos(_geocentricLongitude(_venus, d, sunState), glyph: '♀', label: 'ศุกร์', color: const Color(0xFFF06292)),
      pos(_geocentricLongitude(_mars, d, sunState), glyph: '♂', label: 'อังคาร', color: const Color(0xFFFF6B47)),
      pos(_geocentricLongitude(_jupiter, d, sunState), glyph: '♃', label: 'พฤหัส', color: const Color(0xFFFFB300)),
      pos(_geocentricLongitude(_saturn, d, sunState), glyph: '♄', label: 'เสาร์', color: const Color(0xFF9E9E9E)),
    ];

    return NatalChart._(
      birth: b, sun: sun, moon: moon, ascendant: asc,
      planets: planets, aspectsTo: _aspects(planets),
    );
  }

  // ─── Real aspect detection ─────────────────────────────────
  // Classic Ptolemaic aspects within an orb. Returns the tightest set so
  // the wheel draws genuine geometry, not illustrative lines.
  static const _aspectAngles = <(double, String)>[
    (0, 'conj'), (60, 'sextile'), (90, 'square'),
    (120, 'trine'), (180, 'opposition'),
  ];

  static List<NatalAspect> _aspects(List<NatalPosition> bodies, {double orbLimit = 6}) {
    final found = <NatalAspect>[];
    for (var i = 0; i < bodies.length; i++) {
      for (var j = i + 1; j < bodies.length; j++) {
        var sep = (bodies[i].lon - bodies[j].lon).abs() % 360;
        if (sep > 180) sep = 360 - sep;
        for (final (angle, kind) in _aspectAngles) {
          final orb = (sep - angle).abs();
          if (orb <= orbLimit) {
            found.add(NatalAspect(
              fromLon: bodies[i].lon, toLon: bodies[j].lon,
              kind: kind, orb: orb,
            ));
            break;
          }
        }
      }
    }
    found.sort((a, b) => a.orb.compareTo(b.orb)); // tightest first
    return found;
  }

  // ─── Trig helpers (degrees in, degrees out) ────────────────
  static double _rad(double deg) => deg * math.pi / 180;
  static double _sin(double deg) => math.sin(_rad(deg));
  static double _cos(double deg) => math.cos(_rad(deg));
  static double _atan2(double y, double x) => math.atan2(y, x) * 180 / math.pi;
  static double _mod360(double x) => ((x % 360) + 360) % 360;

  // ─── Sun (Meeus-grade) + its rectangular ecliptic coords ───
  // The Sun's geocentric rectangular position is what turns a planet's
  // heliocentric position into a geocentric one (geo = helio + sun).
  static _SolarState _solarState(double d) {
    final w = 282.9404 + 4.70935e-5 * d;        // longitude of perihelion
    final e = 0.016709 - 1.151e-9 * d;          // eccentricity
    final m = _mod360(356.0470 + 0.9856002585 * d); // mean anomaly

    final eAnom = _kepler(m, e);
    final x = _cos(eAnom) - e;
    final y = _sin(eAnom) * math.sqrt(1 - e * e);
    final r = math.sqrt(x * x + y * y);
    final v = _atan2(y, x);                      // true anomaly
    final lon = _mod360(v + w);                  // true ecliptic longitude
    return _SolarState(lon, r * _cos(lon), r * _sin(lon));
  }

  // ─── Geocentric ecliptic longitude of a planet ─────────────
  static double _geocentricLongitude(_OrbitalElements el, double d, _SolarState sun) {
    final n = el.node0 + el.nodeRate * d;        // longitude of ascending node
    final i = el.incl0 + el.inclRate * d;        // inclination
    final w = el.peri0 + el.periRate * d;        // argument of perihelion
    final a = el.semiMajor;                       // (AU, ~constant)
    final e = el.ecc0 + el.eccRate * d;          // eccentricity
    final m = _mod360(el.meanAnom0 + el.meanAnomRate * d);

    final eAnom = _kepler(m, e);
    final xv = a * (_cos(eAnom) - e);
    final yv = a * math.sqrt(1 - e * e) * _sin(eAnom);
    final v = _atan2(yv, xv);                     // true anomaly
    final r = math.sqrt(xv * xv + yv * yv);       // heliocentric distance

    final vw = v + w;
    // Heliocentric ecliptic rectangular coords (z dropped — longitude only).
    final xh = r * (_cos(n) * _cos(vw) - _sin(n) * _sin(vw) * _cos(i));
    final yh = r * (_sin(n) * _cos(vw) + _cos(n) * _sin(vw) * _cos(i));

    // Shift origin from Sun to Earth, then read off the ecliptic longitude.
    return _mod360(_atan2(yh + sun.y, xh + sun.x));
  }

  /// Solve Kepler's equation E − e·sinE = M (Schlyter's degree form,
  /// Newton-refined). Converges in a handful of steps even for Mercury.
  static double _kepler(double m, double e) {
    var eAnom = m + e * (180 / math.pi) * _sin(m) * (1 + e * _cos(m));
    for (var iter = 0; iter < 12; iter++) {
      final delta = (eAnom - e * (180 / math.pi) * _sin(eAnom) - m) /
          (1 - e * _cos(eAnom));
      eAnom -= delta;
      if (delta.abs() < 1e-7) break;
    }
    return eAnom;
  }

  // ─── Calendar / sidereal helpers ───────────────────────────

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
    return _mod360(lon);
  }

  static double _localSiderealTime(double jd, double lng) {
    final t = (jd - 2451545.0) / 36525.0;
    final gmst = 280.46061837 + 360.98564736629 * (jd - 2451545.0)
        + 0.000387933 * t * t - t * t * t / 38710000.0;
    return _mod360(gmst + lng) / 15.0;
  }

  /// Ascendant — the ecliptic longitude rising on the eastern horizon.
  /// Standard spherical-astronomy formula from the RA of the Midheaven
  /// ([ramc], degrees), geographic [lat] and [obliquity] (all degrees).
  static double _ascendant(double ramc, double lat, double obliquity) {
    final asc = _atan2(
      _cos(ramc),
      -(_sin(ramc) * _cos(obliquity) + _tan(lat) * _sin(obliquity)),
    );
    return _mod360(asc);
  }

  static double _tan(double deg) => math.tan(_rad(deg));
}

/// Sun's geocentric longitude + rectangular ecliptic coords (AU).
class _SolarState {
  const _SolarState(this.lon, this.x, this.y);
  final double lon;
  final double x, y;
}

/// Keplerian elements as a linear function of Schlyter's day number `d`.
class _OrbitalElements {
  const _OrbitalElements({
    required this.node0, required this.nodeRate,
    required this.incl0, required this.inclRate,
    required this.peri0, required this.periRate,
    required this.semiMajor,
    required this.ecc0, required this.eccRate,
    required this.meanAnom0, required this.meanAnomRate,
  });
  final double node0, nodeRate;
  final double incl0, inclRate;
  final double peri0, periRate;
  final double semiMajor;
  final double ecc0, eccRate;
  final double meanAnom0, meanAnomRate;
}

// Orbital elements (epoch 1999-12-31.0 TDT) — Paul Schlyter, "Computing
// planetary positions". Good to ~1–2′ for the inner planets and a few
// arc-minutes for the outer ones across 1900–2100.
const _mercury = _OrbitalElements(
  node0: 48.3313, nodeRate: 3.24587e-5,
  incl0: 7.0047, inclRate: 5.00e-8,
  peri0: 29.1241, periRate: 1.01444e-5,
  semiMajor: 0.387098,
  ecc0: 0.205635, eccRate: 5.59e-10,
  meanAnom0: 168.6562, meanAnomRate: 4.0923344368,
);
const _venus = _OrbitalElements(
  node0: 76.6799, nodeRate: 2.46590e-5,
  incl0: 3.3946, inclRate: 2.75e-8,
  peri0: 54.8910, periRate: 1.38374e-5,
  semiMajor: 0.723330,
  ecc0: 0.006773, eccRate: -1.302e-9,
  meanAnom0: 48.0052, meanAnomRate: 1.6021302244,
);
const _mars = _OrbitalElements(
  node0: 49.5574, nodeRate: 2.11081e-5,
  incl0: 1.8497, inclRate: -1.78e-8,
  peri0: 286.5016, periRate: 2.92961e-5,
  semiMajor: 1.523688,
  ecc0: 0.093405, eccRate: 2.516e-9,
  meanAnom0: 18.6021, meanAnomRate: 0.5240207766,
);
const _jupiter = _OrbitalElements(
  node0: 100.4542, nodeRate: 2.76854e-5,
  incl0: 1.3030, inclRate: -1.557e-7,
  peri0: 273.8777, periRate: 1.64505e-5,
  semiMajor: 5.20256,
  ecc0: 0.048498, eccRate: 4.469e-9,
  meanAnom0: 19.8950, meanAnomRate: 0.0830853001,
);
const _saturn = _OrbitalElements(
  node0: 113.6634, nodeRate: 2.38980e-5,
  incl0: 2.4886, inclRate: -1.081e-7,
  peri0: 339.3939, periRate: 2.97661e-5,
  semiMajor: 9.55475,
  ecc0: 0.055546, eccRate: -9.499e-9,
  meanAnom0: 316.9670, meanAnomRate: 0.0334442282,
);
