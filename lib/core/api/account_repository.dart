import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session.dart';
import 'api_client.dart';
import 'api_exceptions.dart';
import 'app_config_repository.dart';
import 'endpoints.dart';

Map<String, dynamic> accountMap(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
int accountInt(dynamic value) => int.tryParse('$value') ?? 0;

class DailyLuck {
  const DailyLuck({
    required this.checkedIn,
    required this.streak,
    required this.earned,
    this.nextMilestone,
    this.reading,
  });
  final bool checkedIn;
  final int streak;
  final List<Map<String, dynamic>> earned;
  final Map<String, dynamic>? nextMilestone, reading;
  factory DailyLuck.fromJson(Map<String, dynamic> j) => DailyLuck(
    checkedIn: j['checked_in'] == true,
    streak: accountInt(j['streak']),
    earned: (j['earned'] as List? ?? []).map(accountMap).toList(),
    nextMilestone: j['next_milestone'] is Map ? accountMap(j['next_milestone']) : null,
    reading: j['reading'] is Map ? accountMap(j['reading']) : null,
  );
}

class CollectionCard {
  const CollectionCard({
    required this.slug,
    required this.name,
    required this.found,
    required this.count,
    required this.reversedCount,
    this.imageUrl,
  });
  final String slug, name;
  final String? imageUrl;
  final bool found;
  final int count, reversedCount;
  factory CollectionCard.fromJson(Map<String, dynamic> j) => CollectionCard(
    slug: '${j['slug'] ?? ''}',
    name: '${j['name_th'] ?? j['name_en'] ?? ''}',
    found: j['found'] == true,
    count: accountInt(j['count']),
    reversedCount: accountInt(j['reversed_count']),
    imageUrl: j['image_url'] as String?,
  );
}

class CardCollection {
  const CardCollection({
    required this.found,
    required this.total,
    required this.cards,
    this.favourite,
  });
  final int found, total;
  final List<CollectionCard> cards;
  final Map<String, dynamic>? favourite;
  factory CardCollection.fromJson(Map<String, dynamic> j) => CardCollection(
    found: accountInt(j['found']),
    total: accountInt(j['total']),
    cards: (j['cards'] as List? ?? []).map((c) => CollectionCard.fromJson(accountMap(c))).toList(),
    favourite: j['favourite'] is Map ? accountMap(j['favourite']) : null,
  );
}

class AccountProfile {
  const AccountProfile({
    required this.name,
    this.email,
    this.phone,
    this.birthDate,
    this.birthTime,
    this.birthPlace,
    this.lineId,
    this.zodiac,
    this.chineseZodiac,
    this.subscribed = false,
  });
  final String name;
  final String? email, phone, birthDate, birthTime, birthPlace, lineId;
  final Map<String, dynamic>? zodiac, chineseZodiac;
  final bool subscribed;
  factory AccountProfile.fromJson(Map<String, dynamic> j) => AccountProfile(
    name: '${j['name'] ?? ''}',
    email: j['email'] as String?,
    phone: j['phone'] as String?,
    birthDate: j['birth_date'] as String?,
    birthTime: j['birth_time'] as String?,
    birthPlace: j['birth_place'] as String?,
    lineId: j['line_id'] as String?,
    subscribed: j['subscribed'] == true,
    zodiac: j['zodiac'] is Map ? accountMap(j['zodiac']) : null,
    chineseZodiac: j['chinese_zodiac'] is Map ? accountMap(j['chinese_zodiac']) : null,
  );
}

class AccountRepository {
  AccountRepository(this.api);
  final ApiClient api;
  Future<Map<String, dynamic>?> _get(String path) async {
    try {
      return accountMap((await api.get<Map<String, dynamic>>(path))['data']);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<DailyLuck?> dailyLuck() async {
    final j = await _get(Api.accountDailyLuck);
    return j == null ? null : DailyLuck.fromJson(j);
  }

  Future<DailyLuck> checkin() async => DailyLuck.fromJson(
    accountMap((await api.post<Map<String, dynamic>>(Api.accountCheckin))['data']),
  );
  Future<CardCollection?> collection() async {
    final j = await _get(Api.accountCollection);
    return j == null ? null : CardCollection.fromJson(j);
  }

  Future<AccountProfile?> profile() async {
    final j = await _get(Api.accountProfile);
    return j == null ? null : AccountProfile.fromJson(j);
  }

  Future<AccountProfile> saveProfile(Map<String, dynamic> fields) async => AccountProfile.fromJson(
    accountMap((await api.patch<Map<String, dynamic>>(Api.accountProfile, data: fields))['data']),
  );
}

final accountRepositoryProvider = FutureProvider<AccountRepository>(
  (ref) async => AccountRepository(await ref.watch(apiClientProvider.future)),
);
final dailyLuckProvider = FutureProvider.autoDispose<DailyLuck?>((ref) async {
  final user = ref.watch(sessionUserIdProvider);
  final cfg = await ref.watch(appConfigProvider.future);
  if (user == null || !cfg.has('daily_luck')) return null;
  final thai = DateTime.now().toUtc().add(const Duration(hours: 7));
  final midnight = Timer(
    DateTime.utc(thai.year, thai.month, thai.day + 1).difference(thai),
    ref.invalidateSelf,
  );
  ref.onDispose(midnight.cancel);
  return (await ref.watch(accountRepositoryProvider.future)).dailyLuck();
});
final collectionProvider = FutureProvider.autoDispose<CardCollection?>((ref) async {
  final user = ref.watch(sessionUserIdProvider);
  final cfg = await ref.watch(appConfigProvider.future);
  if (user == null || !cfg.has('collection')) return null;
  return (await ref.watch(accountRepositoryProvider.future)).collection();
});
final accountProfileProvider = FutureProvider.autoDispose<AccountProfile?>((ref) async {
  final user = ref.watch(sessionUserIdProvider);
  final cfg = await ref.watch(appConfigProvider.future);
  if (user == null || !cfg.has('account_profile')) return null;
  return (await ref.watch(accountRepositoryProvider.future)).profile();
});
