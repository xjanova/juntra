import 'package:flutter_test/flutter_test.dart';
import 'package:juntra/core/update/update_info.dart';

void main() {
  group('compareSemver', () {
    test('orders by numeric segment', () {
      expect(compareSemver('0.1.3', '0.1.4'), -1);
      expect(compareSemver('0.2.0', '0.1.9'), 1);
      expect(compareSemver('1.0.0', '1.0.0'), 0);
    });
    test('pads missing segments with zero', () {
      expect(compareSemver('1.0', '1.0.0'), 0);
      expect(compareSemver('1.0.1', '1.0'), 1);
    });
    test('strips a pre-release suffix', () {
      expect(compareSemver('1.2.3-beta', '1.2.3'), 0);
    });
    test('is numeric, not lexicographic (10 > 9)', () {
      expect(compareSemver('0.1.10', '0.1.9'), 1);
    });
  });

  group('isReleaseNewer — build number breaks a version tie', () {
    test('a higher version is newer regardless of build', () {
      expect(isReleaseNewer('0.1.3', 7, '0.1.4', 1), isTrue);
      expect(isReleaseNewer('0.1.4', 1, '0.1.3', 99), isFalse);
    });

    test('same version + higher build IS newer (the release:build bug)', () {
      // The exact case the old version-only compare missed.
      expect(isReleaseNewer('0.1.3', 7, '0.1.3', 8), isTrue);
    });

    test('same version + equal-or-lower build is NOT newer', () {
      expect(isReleaseNewer('0.1.3', 7, '0.1.3', 7), isFalse);
      expect(isReleaseNewer('0.1.3', 8, '0.1.3', 7), isFalse);
    });

    test('legacy dismissed marker (build 0) never suppresses a real build', () {
      // A pre-fix skip stored just "0.1.3" → parsed as build 0; a 0.1.3+8
      // release must still count as newer so it re-surfaces.
      expect(isReleaseNewer('0.1.3', 0, '0.1.3', 8), isTrue);
    });
  });
}
