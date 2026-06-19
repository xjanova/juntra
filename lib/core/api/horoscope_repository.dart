import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'endpoints.dart';

/// Daily horoscope — free, read-only `/v1/horoscope*`. Replaces the app's
/// previously-hardcoded "ดวงรายวัน" with the backend's AI-generated content.
class HoroscopeRepository {
  HoroscopeRepository(this._api);
  final ApiClient _api;

  Future<List<Map<String, dynamic>>> signs() async {
    final res = await _api.get<Map<String, dynamic>>(Api.horoscopeIndex);
    final data = res['data'];
    return data is List
        ? data.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
        : const [];
  }

  Future<Map<String, dynamic>> daily(String slug) async {
    final res = await _api.get<Map<String, dynamic>>(Api.horoscope(slug));
    final data = res['data'];
    return data is Map<String, dynamic> ? data : const {};
  }
}

final horoscopeRepositoryProvider = FutureProvider<HoroscopeRepository>((ref) async {
  final api = await ref.watch(apiClientProvider.future);
  return HoroscopeRepository(api);
});

final horoscopeSignsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = await ref.watch(horoscopeRepositoryProvider.future);
  return repo.signs();
});

final dailyHoroscopeProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, slug) async {
  final repo = await ref.watch(horoscopeRepositoryProvider.future);
  return repo.daily(slug);
});
