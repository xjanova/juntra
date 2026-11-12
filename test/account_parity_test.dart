import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:juntra/core/api/account_repository.dart';
import 'package:juntra/core/api/api_client.dart';
import 'package:juntra/core/api/app_config_repository.dart';
import 'package:juntra/core/api/endpoints.dart';
import 'package:juntra/core/api/push_repository.dart';
import 'package:juntra/core/api/wallet_repository.dart';
import 'package:juntra/core/auth/session.dart';
import 'package:juntra/core/push/push_bootstrap.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final FutureOr<(int, Map<String, dynamic>)> Function(RequestOptions) respond;
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final (status, body) = await respond(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<ApiClient> client(_Adapter adapter) async {
    final api = await ApiClient.create();
    api.dio.interceptors.clear();
    api.dio.httpClientAdapter = adapter;
    addTearDown(api.dio.close);
    return api;
  }

  test('checkin reads the real daily blessing, including a zero-prefixed number', () async {
    final api = await client(
      _Adapter(
        (_) => (
          200,
          {
            'data': {
              'new': true,
              'checked_in': true,
              'streak': 7,
              'next_milestone': {'days': 14, 'label': 'สองสัปดาห์', 'left': 7},
              'earned': [
                {'days': 7, 'label': 'ครบสัปดาห์'},
              ],
              'reading': {
                'day_name': 'พฤหัสบดี',
                'day_color': {'name': 'ส้ม', 'hex': '#ffaa00'},
                'lucky_color': {'name': 'ฟ้า', 'hex': '#7cc7f6'},
                'number': '07',
                'direction': 'ตะวันออก',
                'blessing': 'ขอให้วันนี้ราบรื่น',
              },
            },
          },
        ),
      ),
    );
    final luck = await AccountRepository(api).checkin();
    expect(luck.checkedIn, isTrue);
    expect(luck.reading?['number'], '07');
    expect(luck.nextMilestone?['left'], 7);
    expect(luck.earned.single['days'], 7);
  });

  test('old server 404 hides account feature instead of showing broken data', () async {
    final api = await client(_Adapter((_) => (404, {'message': 'Not found'})));
    final repo = AccountRepository(api);
    expect(await repo.dailyLuck(), isNull);
    expect(await repo.collection(), isNull);
    expect(await repo.profile(), isNull);
  });

  test('late unauthorized response from old account cannot erase new login token', () async {
    FlutterSecureStorage.setMockInitialValues({'juntra_auth_token': 'old-login'});
    final api = await ApiClient.create();
    addTearDown(api.dio.close);
    api.dio.httpClientAdapter = _Adapter((request) async {
      expect(request.headers['Authorization'], 'Bearer old-login');
      await api.setToken('new-login');
      return (401, {'message': 'expired'});
    });
    await expectLater(
      api.post<Map<String, dynamic>>(
        Api.pushDevices,
        data: {'token': 'device'},
        sessionToken: 'old-login',
      ),
      throwsA(isA<Exception>()),
    );
    expect(await api.getToken(), 'new-login');
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('account data reloads on account switch and never fetches for a guest', () async {
    var calls = 0;
    final adapter = _Adapter(
      (_) => (
        200,
        {
          'data': {'streak': ++calls},
        },
      ),
    );
    final api = await client(adapter);
    final identity = StateProvider<String?>((ref) => 'alice');
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWith((ref) async => api),
        appConfigProvider.overrideWith(
          (ref) async => const AppConfig(services: {}, features: {'daily_luck': true}),
        ),
        sessionUserIdProvider.overrideWith((ref) => ref.watch(identity)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(dailyLuckProvider, (_, _) {});
    expect((await container.read(dailyLuckProvider.future))?.streak, 1);
    container.read(identity.notifier).state = 'bob';
    expect((await container.read(dailyLuckProvider.future))?.streak, 2);
    container.read(identity.notifier).state = null;
    expect(await container.read(dailyLuckProvider.future), isNull);
    expect(calls, 2);
  });

  test('profile uses PATCH and preserves omitted login credentials', () async {
    final adapter = _Adapter(
      (request) => (
        200,
        {
          'data': {
            ...request.data as Map,
            'name': 'จันทรา',
            'email': 'owner@example.test',
            'phone': '0812345678',
          },
        },
      ),
    );
    final api = await client(adapter);
    final profile = await AccountRepository(
      api,
    ).saveProfile({'birth_date': '2000-01-01', 'birth_time': null});
    expect(adapter.requests.single.method, 'PATCH');
    expect(adapter.requests.single.path, Api.accountProfile);
    expect(adapter.requests.single.data, {'birth_date': '2000-01-01', 'birth_time': null});
    expect(profile.email, 'owner@example.test');
  });

  test('collection retains unfound card names while found flag controls reveal', () {
    final collection = CardCollection.fromJson({
      'found': 0,
      'total': 78,
      'favourite': null,
      'cards': [
        {
          'slug': 'the-fool',
          'name_th': 'เดอะฟูล',
          'image_url': 'https://example.test/card.webp',
          'found': false,
          'count': 0,
          'reversed_count': 0,
        },
      ],
    });
    expect(collection.cards.single.name, 'เดอะฟูล');
    expect(collection.cards.single.found, isFalse);
    expect(collection.favourite, isNull);
  });

  test('push settings only PUT muted, leaving admin quiet hours unchanged', () async {
    final adapter = _Adapter(
      (request) => (
        200,
        {
          'data': {
            ...request.data as Map,
            'types': [
              {'key': 'daily', 'name': 'ดวงรายวัน'},
            ],
            'quiet': {'start': '21:00', 'end': '08:00'},
            'fcm': true,
          },
        },
      ),
    );
    final prefs = await PushRepository(await client(adapter)).save({'daily'});
    expect(adapter.requests.single.data, {
      'muted': ['daily'],
    });
    expect(prefs.quietStart, '21:00');
    expect(prefs.muted, {'daily'});
  });

  test('push routes allow only internal destinations and positive ids', () {
    expect(pushRoute({'reading_id': '12', 'url': 'https://evil.test'}), '/reading?id=12');
    expect(pushRoute({'conversation_id': 6}), '/chat?id=6');
    expect(pushRoute({'reading_id': -1, 'url': 'javascript:evil()'}), isNull);
    expect(pushRoute({'type': 'daily'}), '/daily-luck');
    expect(pushRoute({'url': 'https://evil.test'}), isNull);
    expect(
      pushRoute({'type': 'reading_ready', 'url': 'https://xn--82c4af5bzdj.online/reading/42'}),
      '/reading?id=42',
    );
    expect(
      pushRoute({'url': 'https://xn--82c4af5bzdj.online/account/dashboard#daily-luck'}),
      '/daily-luck',
    );
    expect(pushRoute({'url': 'https://evil.test/reading/42'}), isNull);
    expect(
      pushRoute({'url': 'https://xn--82c4af5bzdj.online/wallet/topup/42', 'type': 'bill'}),
      isNull,
    );
  });

  test('server can turn off all external topup channels', () {
    final cfg = WalletTopupConfig.fromJson({'bundles': [], 'channels': [], 'min': 50, 'max': 100});
    expect(cfg.channels, isEmpty);
    expect(cfg.bundles, isEmpty);
    expect(cfg.hasKbank, isFalse);
    final bank = KbankAccount.fromJson({'number': '1234567890', 'display_number': '123-4-56789-0'});
    expect(bank?.number, '1234567890');
    expect(bank?.displayNumber, '123-4-56789-0');
  });
}
