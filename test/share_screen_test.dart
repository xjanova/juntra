import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:juntra/core/api/api_exceptions.dart';
import 'package:juntra/core/api/app_config_repository.dart';
import 'package:juntra/core/api/fortune_repository.dart';
import 'package:juntra/core/api/reading_engagement_repository.dart';
import 'package:juntra/core/auth/session.dart';
import 'package:juntra/features/share/share_screen.dart';

import 'reading_test_support.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  String? copied;
  setUp(() {
    copied = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );

  Future<void> mount(
    WidgetTester tester,
    ParityApi api, {
    bool feature = true,
  }) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('home')),
        ),
        GoRoute(
          path: '/share',
          builder: (_, _) => const ShareScreen(readingId: 1),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWithValue('a'),
          appConfigValueProvider.overrideWithValue(
            AppConfig(services: const {}, features: {'reading_share': feature}),
          ),
          readingDetailProvider(1).overrideWith((ref) async => {'id': 1, 'type': 'tarot_single', 'status': 'done', 'result': 'คำทำนาย'}),
          readingEngagementRepositoryProvider.overrideWith(
            (ref) async => ReadingEngagementRepository(api),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    router.push('/share');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets(
    'share opens public link before copying and blocks duplicate taps',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      final api = ParityApi()..onPost = (_) => pending.future;
      await mount(tester, api);
      expect(find.text('LINE'), findsOneWidget);
      expect(find.text('Facebook'), findsOneWidget);
      expect(find.text('Twitter'), findsNothing);
      await tester.tap(find.text('คัดลอกลิงก์'));
      await tester.pump();
      await tester.tap(find.text('คัดลอกลิงก์'), warnIfMissed: false);
      expect(api.calls, hasLength(1));
      expect(api.calls.single.data, {'public': true});
      expect(copied, isNull);
      const url = 'https://xn--82c4af5bzdj.online/tarot/result/1';
      pending.complete({
        'data': {'public': true, 'url': url},
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(copied, url);
    },
  );

  testWidgets('share API 404 copies text with no private result link', (
    tester,
  ) async {
    final api = ParityApi()
      ..onPost = (_) =>
          throw ApiException(statusCode: 404, message: 'Not found');
    await mount(tester, api);
    await tester.tap(find.text('คัดลอกลิงก์'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(copied, isNotNull);
    expect(copied, isNot(contains('http')));
  });

  testWidgets('missing flag shares text without requesting an endpoint', (
    tester,
  ) async {
    final api = ParityApi();
    await mount(tester, api, feature: false);
    await tester.tap(find.text('คัดลอกข้อความ'));
    await tester.pump();
    expect(api.calls, isEmpty);
    expect(copied, isNot(contains('http')));
  });
}
