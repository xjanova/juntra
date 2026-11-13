import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:juntra/core/api/api_exceptions.dart';
import 'package:juntra/core/api/app_config_repository.dart';
import 'package:juntra/core/api/free_card_repository.dart';
import 'package:juntra/core/auth/session.dart';
import 'package:juntra/features/free_card/free_card_screen.dart';
import 'package:juntra/shared/widgets/gold_button.dart';

import 'reading_test_support.dart';

const enabled = AppConfig(
  services: {'tarot': true},
  features: {'free_reading': true},
  freeReading: true,
);
final userProvider = StateProvider<String?>((ref) => 'a');

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('D1 reasons and optional limits parse without enabling old servers', () {
    expect(
      FreeCardState.fromJson(const {
        'available': true,
        'max_chars': 120,
      }).maxChars,
      120,
    );
    expect(FreeCardState.fromJson(const {'max_chars': -1}).maxChars, isNull);
    for (final reason in [
      'claimed',
      'disabled',
      'daily_cap',
      'in_flight',
      'guest',
    ]) {
      final state = FreeCardState.fromJson({'reason': reason});
      expect(state.available, isFalse);
      expect(state.reasonText(), isNotEmpty);
    }
    expect(FreeCardState.fromJson(const {'reason': 'claimed'}).claimed, isTrue);
    expect(FreeCardState.unsupported.supported, isFalse);
    expect(
      FreeCardState.fromJson(const {
        'reason': 'daily_cap',
        'message': 'พรุ่งนี้มาใหม่นะคะ',
      }).reasonText(),
      'พรุ่งนี้มาใหม่นะคะ',
    );
  });

  test(
    'D2 result unwraps reading and resume conversation; malformed response rejected',
    () {
      final result = FreeCardResult.fromJson({
        'data': {
          'reading': {'id': 10},
          'conversation_id': 20,
        },
      })!;
      expect(result.readingId, 10);
      expect(result.conversationId, 20);
      expect(FreeCardResult.fromJson({'data': {}}), isNull);
    },
  );

  test(
    'GET 404 is unsupported, claim sends trimmed question and idempotency',
    () async {
      final api = ParityApi()
        ..onGet = (_) {
          throw ApiException(statusCode: 404, message: 'Not found');
        }
        ..onPost = (_) => {
          'data': {
            'reading': {'id': 10},
            'conversation_id': 20,
          },
        };
      final repo = FreeCardRepository(api);
      expect((await repo.status()).supported, isFalse);
      await repo.claim(question: ' งาน ', idempotencyKey: 'same-key');
      expect(api.calls.single.key, 'same-key');
      expect(api.calls.single.data, {'question': 'งาน'});
    },
  );

  Future<ProviderContainer> mount(
    WidgetTester tester, {
    AppConfig config = enabled,
    String? user = 'a',
    ParityApi? api,
    GoRouter? router,
  }) async {
    final container = ProviderContainer(
      overrides: [
        appConfigValueProvider.overrideWithValue(config),
        sessionUserIdProvider.overrideWith((ref) => ref.watch(userProvider)),
        freeCardRepositoryProvider.overrideWith(
          (ref) async => FreeCardRepository(
            api ??
                (ParityApi()
                  ..onGet = (_) => {
                    'data': {'available': true, 'max_chars': 5},
                  }),
          ),
        ),
      ],
    );
    container.read(userProvider.notifier).state = user;
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: router == null
            ? const MaterialApp(home: FreeCardScreen())
            : MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    return container;
  }

  testWidgets('feature gate and guest never fetch private eligibility', (
    tester,
  ) async {
    var gets = 0;
    final api = ParityApi()
      ..onGet = (_) {
        gets++;
        return {};
      };
    await mount(tester, config: AppConfig.fallback, api: api);
    expect(find.text('ยังไม่เปิดให้บริการ'), findsOneWidget);
    expect(gets, 0);
    await tester.pumpWidget(const SizedBox());
    await mount(tester, user: null, api: api);
    expect(find.text('เข้าสู่ระบบ'), findsOneWidget);
    expect(gets, 0);
  });

  testWidgets('404 is friendly with no claim button', (tester) async {
    await mount(
      tester,
      api: ParityApi()
        ..onGet = (_) =>
            throw ApiException(statusCode: 404, message: 'Not found'),
    );
    expect(find.text('ยังไม่เปิดให้บริการ'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets(
    '500 question chars independent of max_chars, double tap and retry handoff',
    (tester) async {
      final response = Completer<Map<String, dynamic>>();
      final api = ParityApi()
        ..onGet = (_) {
          return {
            'data': {'available': true, 'max_chars': 5},
          };
        }
        ..onPost = (_) => response.future;
      final router = GoRouter(
        initialLocation: '/free-card',
        routes: [
          GoRoute(
            path: '/free-card',
            builder: (_, _) => const FreeCardScreen(),
          ),
          GoRoute(
            path: '/reading',
            builder: (_, state) => Scaffold(
              body: Text('reading ${state.uri.queryParameters['id']}'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      final container = await mount(tester, api: api, router: router);
      await tester.enterText(
        find.byType(TextField),
        List.filled(501, 'a').join(),
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        List.filled(500, 'a').join(),
      );
      final claim = find.byWidgetPredicate(
        (w) => w is GoldButton && w.label == 'รับไพ่ฟรี 1 ใบ',
      );
      await tester.ensureVisible(claim);
      await tester.tap(claim);
      await tester.pump();
      await tester.tap(find.byType(GoldButton));
      expect(api.calls.length, 1);
      response.completeError(
        ApiException(statusCode: 0, message: 'หมดเวลาเชื่อมต่อ'),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('หมดเวลาเชื่อมต่อ'), findsOneWidget);
      api.onPost = (_) => {
        'data': {
          'reading': {'id': 10},
          'conversation_id': 20,
        },
      };
      await tester.ensureVisible(claim);
      await tester.tap(claim);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.calls.length, 2);
      expect(api.calls[1].key, api.calls[0].key);
      expect(container.read(freeCardConversationsProvider)[10], 20);
      expect(find.text('reading 10'), findsOneWidget);
    },
  );

  testWidgets(
    'account switch discards a pending result and conversation cache',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      final api = ParityApi()
        ..onGet = (_) {
          return {
            'data': {'available': true},
          };
        }
        ..onPost = (_) => pending.future;
      final container = await mount(tester, api: api);
      await tester.ensureVisible(find.text('รับไพ่ฟรี 1 ใบ'));
      await tester.tap(find.text('รับไพ่ฟรี 1 ใบ'));
      await tester.pump();
      container.read(freeCardConversationsProvider.notifier).state = {1: 2};
      container.read(userProvider.notifier).state = 'b';
      await tester.pump();
      pending.complete({
        'data': {
          'reading': {'id': 10},
          'conversation_id': 20,
        },
      });
      await tester.pump();
      expect(container.read(freeCardConversationsProvider), isEmpty);
      expect(tester.takeException(), isNull);
      expect(find.text('รับไพ่ฟรี 1 ใบ'), findsOneWidget);
    },
  );
}
