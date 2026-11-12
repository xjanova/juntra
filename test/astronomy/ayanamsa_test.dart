import 'package:flutter_test/flutter_test.dart';
import 'package:juntra/core/astronomy/ayanamsa.dart';
import 'package:juntra/core/astronomy/natal_chart.dart';

void main() {
  test('ThaiAstro PHP vectors at January 1 UTC', () {
    const vectors = {1900: 22.455409561456, 1950: 23.153854780728,
      2000: 23.852300000000, 2026: 24.215520580847, 2100: 25.249228684367};
    for (final vector in vectors.entries) {
      expect(thaiAyanamsa(DateTime.utc(vector.key)), closeTo(vector.value, 1e-11));
    }
  });
  test('default chart rotates every longitude and ascendant to Thai sidereal', () {
    const birth = BirthData(year: 2000, month: 1, day: 1, hour: 7, minute: 0,
      lat: 13.7563, lng: 100.5018, placeName: 'กรุงเทพมหานคร', tzOffsetHours: 7);
    final thai = NatalChart.compute(birth);
    final tropical = NatalChart.compute(birth, zodiac: ZodiacSystem.tropical);
    for (var i = 0; i < thai.planets.length; i++) {
      expect(thai.planets[i].lon, closeTo((tropical.planets[i].lon - 23.8523 + 360) % 360, 1e-9));
    }
    expect(thai.ascendant.lon, closeTo((tropical.ascendant.lon - 23.8523 + 360) % 360, 1e-9));
    expect(thai.sun.signIdx, 8);
    expect(tropical.sun.signIdx, 9);
  });
}
