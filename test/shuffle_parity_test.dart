import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:juntra/core/auth/auth_state.dart';
import 'package:juntra/core/auth/session.dart';
import 'package:juntra/features/shuffle/shuffle_screen.dart';
import 'package:juntra/core/api/api_exceptions.dart';
import 'package:juntra/core/api/app_config_repository.dart';
import 'package:juntra/core/api/fortune_repository.dart';
import 'package:juntra/core/api/idempotency.dart';
import 'package:juntra/core/api/rooms_repository.dart';
import 'package:juntra/core/api/tarot_catalog_repository.dart';
import 'package:juntra/core/api/tarot_packages_repository.dart';
import 'package:juntra/core/app_channel.dart';
import 'package:juntra/features/shuffle/shuffle_pricing.dart';
import 'package:juntra/features/spreads/package_groups.dart';

import 'reading_test_support.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> mount(
    WidgetTester tester, {
    bool webOnly = false,
    required ParityApi api,
  }) async {
    final package = TarotPackage.fromJson({
      'key': 'single',
      'name_th': 'ไพ่ใบเดียว',
      'cards': 1,
      'positions': const ['คำตอบ'],
      'web_only': webOnly,
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWithValue('a'),
          authControllerProvider.overrideWith((ref) => _SignedIn()),
          appConfigValueProvider.overrideWithValue(AppConfig.fallback),
          tarotPackageProvider('single').overrideWith((ref) async => package),
          tarotCatalogProvider.overrideWith((ref) async => TarotCatalog.empty),
          tarotCatalogRepositoryProvider.overrideWith(
            (ref) async => TarotCatalogRepository(api),
          ),
        ],
        child: const MaterialApp(home: ShuffleScreen(spreadId: 'single')),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'Play deep link to web-only package cannot start purchase or link to web',
    (tester) async {
      final api = ParityApi();
      await mount(tester, webOnly: true, api: api);
      expect(find.text('เริ่มสับไพ่'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(api.calls, isEmpty);
    },
  );

  testWidgets(
    'deal 404 waits for cinematic then shows retry without local picks',
    (tester) async {
      final api = ParityApi()
        ..onPost = (_) =>
            throw ApiException(statusCode: 404, message: 'ยังไม่พร้อมค่ะ');
      await mount(tester, api: api);
      final start = find.text('เริ่มสับไพ่');
      await tester.ensureVisible(start);
      await tester.tap(start);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 2300));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('ยังไม่พร้อมค่ะ'), findsOneWidget);
      expect(find.text('ลองสับใหม่'), findsOneWidget);
      expect(find.textContaining('เลือกไพ่ 1 ใบจากสำรับ'), findsNothing);
      expect(api.calls, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    },
  );
  test(
    'premium is opt-in and total includes voice price with credit label',
    () {
      const offer = VoicePremiumOffer(
        offerable: true,
        price: 100,
        qaMinutes: 20,
      );
      expect(confirmTotal(price: 39, premium: offer), 39);
      expect(confirmTotal(price: 39, premium: offer, premiumOn: true), 139);
      expect(
        confirmPriceSuffix(price: 39, premium: offer, premiumOn: true),
        isPlayChannel ? ' · 139 เครดิต' : ' · ฿139',
      );
      expect(
        confirmPriceSuffix(price: null, premium: offer, premiumOn: true),
        isPlayChannel ? ' · +100 เครดิต' : ' · +฿100',
      );
      expect(voicePremiumLabel(offer), contains('ถามต่อ 20 นาที'));
    },
  );

  test(
    'server alone supplies complete unique deck, missing/malformed deals cannot draw',
    () async {
      final api = ParityApi()
        ..onPost = (_) => {
          'data': {
            'deal_token': 't',
            'cards': List.generate(
              78,
              (i) => {'slug': 'card-$i', 'reversed': i.isOdd},
            ),
          },
        };
      final repo = TarotCatalogRepository(api);
      final deal = await repo.deal();
      expect(deal!.cards[1].reversed, isTrue);
      expect(deal.cards[1].slug, 'card-1');
      api.onPost = (_) => {
        'data': {
          'deal_token': 't',
          'cards': [
            {'slug': 'a'},
          ],
        },
      };
      expect(await repo.deal(), isNull);
      api.onPost = (_) => {
        'data': {
          'deal_token': 't',
          'cards': List.filled(78, {'slug': 'same'}),
        },
      };
      expect(await repo.deal(), isNull);
      api.onPost = (_) =>
          throw ApiException(statusCode: 404, message: 'Not found');
      await expectLater(repo.deal(), throwsA(isA<ApiException>()));
    },
  );

  test(
    'tarot purchase preserves server slots and premium opt-in with same retry key',
    () async {
      final api = ParityApi()
        ..onPost = (_) => {
          'data': {'id': 5, 'status': 'pending'},
        };
      final repo = FortuneRepository(api);
      final attempt = IdempotentAttempt('tarot');
      final key = attempt.begin('deal|1,3|voice');
      for (var i = 0; i < 2; i++) {
        await repo.createTarotReading(
          type: 'tarot_three',
          picks: [],
          idempotencyKey: attempt.begin('deal|1,3|voice'),
          dealToken: 'deal',
          slots: [1, 3],
          voicePremium: true,
        );
      }
      expect(api.calls.map((c) => c.key), everyElement(key));
      expect(api.calls.first.data['slots'], [1, 3]);
      expect(api.calls.first.data['voice_premium'], isTrue);
      expect(api.calls.first.data['mode'], 'async');
      expect(attempt.begin('deal|1,3|no-voice'), isNot(key));
    },
  );

  test('web-only packages never appear in reader groups', () {
    TarotPackage package(String key, String room, {bool webOnly = false}) =>
        TarotPackage.fromJson({
          'key': key,
          'cards': 1,
          'positions': const ['คำตอบ'],
          'room': room,
          'web_only': webOnly,
        });
    final groups = groupByReader([
      package('quick', 'busaba'),
      package('single', 'maemor'),
      package('secret', 'maemor', webOnly: true),
    ], RoomsState(rooms: OracleRoom.keys.map(OracleRoom.builtIn).toList()));
    expect(groups.first.roomKey, 'busaba');
    expect(groups.expand((g) => g.packages).map((p) => p.key), [
      'quick',
      'single',
    ]);
  });
}

class _SignedIn extends StateNotifier<AuthState> implements AuthController {
  _SignedIn() : super(const AuthAuthenticated(userId: 'a', displayName: 'คุณ'));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
