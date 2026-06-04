import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'natal_chart.dart';

/// Persists the user's birth data locally.
///
/// Birth data is the *input* to the natal chart, not a secret — it never
/// leaves the device (the chart is computed on-device in [NatalChart]) — so
/// plain `shared_preferences` is the right store. If a server-side natal
/// endpoint is added later, this is also the cache that feeds it.
class BirthDataStore {
  const BirthDataStore();

  static const _key = 'natal_birth_data_v1';

  /// A gentle default so a first-time user sees a populated wheel instead of
  /// an empty form. Replaced the moment they save their own data.
  static const demo = BirthData(
    year: 1995, month: 11, day: 14,
    hour: 8, minute: 30,
    lat: 13.7563, lng: 100.5018,
    placeName: 'กรุงเทพมหานคร', tzOffsetHours: 7,
  );

  Future<BirthData?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      return _decode(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null; // corrupt / out-of-schema payload — treat as unset
    }
  }

  Future<void> save(BirthData b) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(_encode(b)));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  static Map<String, dynamic> _encode(BirthData b) => {
        'year': b.year, 'month': b.month, 'day': b.day,
        'hour': b.hour, 'minute': b.minute,
        'lat': b.lat, 'lng': b.lng,
        'placeName': b.placeName, 'tzOffsetHours': b.tzOffsetHours,
      };

  static BirthData _decode(Map<String, dynamic> m) => BirthData(
        year: (m['year'] as num).toInt(),
        month: (m['month'] as num).toInt(),
        day: (m['day'] as num).toInt(),
        hour: (m['hour'] as num).toInt(),
        minute: (m['minute'] as num).toInt(),
        lat: (m['lat'] as num).toDouble(),
        lng: (m['lng'] as num).toDouble(),
        placeName: m['placeName'] as String? ?? '',
        tzOffsetHours: (m['tzOffsetHours'] as num?)?.toDouble() ?? 7,
      );
}

/// Current birth data + whether it's the user's own (vs the demo default).
class BirthDataState {
  const BirthDataState({required this.data, required this.isCustom});
  final BirthData data;
  final bool isCustom;
}

class BirthDataController extends StateNotifier<BirthDataState> {
  BirthDataController(this._store)
      : super(const BirthDataState(data: BirthDataStore.demo, isCustom: false)) {
    _restore();
  }
  final BirthDataStore _store;

  Future<void> _restore() async {
    final saved = await _store.load();
    if (saved != null) {
      state = BirthDataState(data: saved, isCustom: true);
    }
  }

  /// Persist [b] and flip to the user's own data immediately.
  Future<void> save(BirthData b) async {
    await _store.save(b);
    state = BirthDataState(data: b, isCustom: true);
  }
}

final birthDataStoreProvider =
    Provider<BirthDataStore>((ref) => const BirthDataStore());

final birthDataProvider =
    StateNotifierProvider<BirthDataController, BirthDataState>((ref) {
  return BirthDataController(ref.read(birthDataStoreProvider));
});

/// A handful of major Thai locations so the editor never has to ask a user
/// for raw latitude/longitude. All of Thailand is UTC+7.
class BirthPlace {
  const BirthPlace(this.name, this.lat, this.lng);
  final String name;
  final double lat;
  final double lng;
}

const kThaiBirthPlaces = <BirthPlace>[
  BirthPlace('กรุงเทพมหานคร', 13.7563, 100.5018),
  BirthPlace('นนทบุรี', 13.8591, 100.5217),
  BirthPlace('ชลบุรี', 13.3611, 100.9847),
  BirthPlace('เชียงใหม่', 18.7883, 98.9853),
  BirthPlace('เชียงราย', 19.9105, 99.8406),
  BirthPlace('พิษณุโลก', 16.8211, 100.2659),
  BirthPlace('นครสวรรค์', 15.7047, 100.1372),
  BirthPlace('ขอนแก่น', 16.4419, 102.8360),
  BirthPlace('นครราชสีมา', 14.9799, 102.0978),
  BirthPlace('อุดรธานี', 17.4138, 102.7870),
  BirthPlace('อุบลราชธานี', 15.2448, 104.8473),
  BirthPlace('สุราษฎร์ธานี', 9.1382, 99.3217),
  BirthPlace('ภูเก็ต', 7.8804, 98.3923),
  BirthPlace('นครศรีธรรมราช', 8.4304, 99.9631),
  BirthPlace('สงขลา (หาดใหญ่)', 7.0086, 100.4747),
];
