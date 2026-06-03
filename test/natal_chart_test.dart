import 'package:flutter_test/flutter_test.dart';
import 'package:juntra/core/astronomy/natal_chart.dart';

/// UT birth data (tz 0) for a given instant — keeps the astronomy in UT so
/// it can be checked against published ephemerides.
BirthData _ut(int y, int mo, int d, int h, [int mi = 0]) => BirthData(
      year: y, month: mo, day: d, hour: h, minute: mi,
      lat: 0, lng: 0, placeName: 'UT', tzOffsetHours: 0,
    );

/// Smallest angular separation between two ecliptic longitudes (0..180).
double _sep(double a, double b) {
  var s = (a - b).abs() % 360;
  return s > 180 ? 360 - s : s;
}

void main() {
  group('Sun longitude at the 2000 cardinal points', () {
    // The Sun's ecliptic longitude is 0/90/180/270 at the equinoxes and
    // solstices — independent, textbook astronomy.
    void check(String label, BirthData when, double expected) {
      test(label, () {
        final lon = NatalChart.compute(when).sun.lon;
        expect(_sep(lon, expected), lessThan(1.5),
            reason: 'Sun at $label was $lon°, expected ≈$expected°');
      });
    }

    check('vernal equinox', _ut(2000, 3, 20, 7, 35), 0);
    check('summer solstice', _ut(2000, 6, 21, 1, 48), 90);
    check('autumnal equinox', _ut(2000, 9, 22, 17, 28), 180);
    check('winter solstice', _ut(2000, 12, 21, 13, 37), 270);
  });

  group('Great Conjunctions of Jupiter & Saturn', () {
    test('2000-05-28 — conjunction in Taurus (~52°)', () {
      final c = NatalChart.compute(_ut(2000, 5, 28, 16));
      final jup = c.planets[5].lon;
      final sat = c.planets[6].lon;
      expect(_sep(jup, sat), lessThan(2.0),
          reason: 'Jup $jup° vs Sat $sat° should be ~conjunct');
      expect(jup, inInclusiveRange(48, 58)); // Taurus
      expect(sat, inInclusiveRange(48, 58));
    });

    test('2020-12-21 — the "great" conjunction (~300°, < 0.5°)', () {
      final c = NatalChart.compute(_ut(2020, 12, 21, 18));
      final jup = c.planets[5].lon;
      final sat = c.planets[6].lon;
      expect(_sep(jup, sat), lessThan(1.0));
      expect(jup, inInclusiveRange(298, 303)); // 0° Aquarius ≈ 300°
      expect(sat, inInclusiveRange(298, 303));
    });
  });

  group('Inner-planet elongation never exceeds the physical maximum', () {
    // Mercury can never appear > ~28° from the Sun, Venus > ~47°. A strong
    // end-to-end check on the geocentric conversion across many dates.
    test('Mercury ≤ 28°, Venus ≤ 47° over a multi-year sweep', () {
      for (var year = 1995; year <= 2025; year += 5) {
        for (var doy = 1; doy <= 360; doy += 29) {
          final month = ((doy - 1) ~/ 30) + 1;
          final day = ((doy - 1) % 30) + 1;
          final c = NatalChart.compute(_ut(year, month, day, 12));
          final sun = c.sun.lon;
          expect(_sep(c.planets[2].lon, sun), lessThan(29.0),
              reason: 'Mercury elongation $year-$month-$day');
          expect(_sep(c.planets[3].lon, sun), lessThan(48.5),
              reason: 'Venus elongation $year-$month-$day');
        }
      }
    });
  });

  group('Structural invariants', () {
    final c = NatalChart.compute(_ut(1995, 11, 14, 1, 30));

    test('every body has a normalized longitude and matching sign', () {
      for (final p in [c.sun, c.moon, c.ascendant, ...c.planets]) {
        expect(p.lon, inInclusiveRange(0, 360));
        expect(p.signIdx, (p.lon ~/ 30) % 12);
        expect(p.degInSign, inInclusiveRange(0, 30));
      }
    });

    test('aspect kinds actually match the geometry', () {
      const exact = {
        'conj': 0.0, 'sextile': 60.0, 'square': 90.0,
        'trine': 120.0, 'opposition': 180.0,
      };
      for (final a in c.aspectsTo) {
        final sep = _sep(a.fromLon, a.toLon);
        expect((sep - exact[a.kind]!).abs(), lessThanOrEqualTo(6.0001),
            reason: '${a.kind}: separation $sep° out of orb');
        expect(a.orb, closeTo((sep - exact[a.kind]!).abs(), 1e-6));
      }
    });
  });

  test('Kepler solver stays sane for eccentric Mercury', () {
    // Mercury (e≈0.21) is the toughest Kepler case — just make sure the
    // longitude is finite and normalized on a spread of dates.
    for (var d = 0; d < 88; d += 7) {
      final lon = NatalChart.compute(_ut(2010, 1, 1 + d % 27, 0)).planets[2].lon;
      expect(lon.isFinite, isTrue);
      expect(lon, inInclusiveRange(0, 360));
    }
  });
}
