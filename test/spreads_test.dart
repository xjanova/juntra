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
    'quick': 3,
    'love': 5,
    'career': 5,
    'decision': 5,
    'celtic': 10,
    'year': 12,
    'kunsai': 10,
  };

  // config/chat_rooms.php — Busaba reads every spread under 10 cards (PR 58),
  // แม่หมอ keeps celtic + year, the คุณไสย room owns kunsai.
  const rooms = {
    'single': 'busaba',
    'three': 'busaba',
    'quick': 'busaba',
    'love': 'busaba',
    'career': 'busaba',
    'decision': 'busaba',
    'celtic': 'maemor',
    'year': 'maemor',
    'kunsai': 'kunsai',
  };

  test('each fallback spread names the oracle room the web uses', () {
    for (final s in spreads) {
      expect(s.room, rooms[s.id], reason: 'room for ${s.id}');
    }
  });

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
