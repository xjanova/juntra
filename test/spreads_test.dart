import 'package:flutter_test/flutter_test.dart';
import 'package:juntra/shared/data/spreads.dart';

/// Guards the app's spread catalog against the juntraweb backend registry
/// (config/tarot_spreads.php). If these drift, the app either sends an
/// unknown `type`/wrong card count (422) or silently fakes a reading.
void main() {
  // key -> card count, mirroring config/tarot_spreads.php.
  const backend = {
    'single': 1,
    'three': 3,
    'love': 5,
    'career': 5,
    'decision': 5,
    'celtic': 10,
    'year': 12,
  };

  test('spreadIds exactly matches the backend spread keys', () {
    expect(spreadIds, backend.keys.toSet());
    expect(spreads.map((s) => s.id).toSet(), backend.keys.toSet());
  });

  test('every spread maps to tarot_<id> with the backend card count', () {
    for (final s in spreads) {
      expect(s.backendType, 'tarot_${s.id}', reason: 'backendType for ${s.id}');
      expect(s.cards, backend[s.id], reason: 'card count for ${s.id}');
      // The shuffle reveal indexes positions[revealIdx]; a short list would
      // throw mid-cinematic, so every slot must have a label.
      expect(s.positions.length, s.cards, reason: 'positions for ${s.id}');
    }
  });
}
