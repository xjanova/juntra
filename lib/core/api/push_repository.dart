import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session.dart';
import 'account_repository.dart';
import 'api_client.dart';
import 'api_exceptions.dart';
import 'app_config_repository.dart';
import 'endpoints.dart';

class PushPreferences {
  const PushPreferences({
    required this.muted,
    required this.types,
    required this.quietStart,
    required this.quietEnd,
    required this.fcm,
  });
  final Set<String> muted;
  final List<Map<String, dynamic>> types;
  final String quietStart, quietEnd;
  final bool fcm;
  factory PushPreferences.fromJson(Map<String, dynamic> j) {
    final quiet = accountMap(j['quiet']);
    return PushPreferences(
      muted: (j['muted'] as List? ?? []).map((e) => '$e').toSet(),
      types: (j['types'] as List? ?? []).map(accountMap).toList(),
      quietStart: '${quiet['start'] ?? ''}',
      quietEnd: '${quiet['end'] ?? ''}',
      fcm: j['fcm'] == true,
    );
  }
}

class PushRepository {
  PushRepository(this.api);
  final ApiClient api;
  Future<PushPreferences?> preferences() async {
    try {
      return PushPreferences.fromJson(
        accountMap((await api.get<Map<String, dynamic>>(Api.pushPreferences))['data']),
      );
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<PushPreferences> save(Set<String> muted) async => PushPreferences.fromJson(
    accountMap(
      (await api.put<Map<String, dynamic>>(
        Api.pushPreferences,
        data: {'muted': muted.toList()},
      ))['data'],
    ),
  );
}

final pushRepositoryProvider = FutureProvider<PushRepository>(
  (ref) async => PushRepository(await ref.watch(apiClientProvider.future)),
);
final pushPreferencesProvider = FutureProvider.autoDispose<PushPreferences?>((ref) async {
  final user = ref.watch(sessionUserIdProvider);
  final cfg = await ref.watch(appConfigProvider.future);
  if (user == null || !cfg.has('push')) return null;
  return (await ref.watch(pushRepositoryProvider.future)).preferences();
});
