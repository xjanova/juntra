import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:juntra/core/api/api_exceptions.dart';
import 'package:juntra/core/api/fortune_repository.dart';
import 'package:juntra/core/api/reading_engagement_repository.dart';
import 'package:juntra/features/reading/reading_aftercare.dart';
import 'package:juntra/features/reading/reading_voice_panel.dart';
import 'package:juntra/shared/widgets/gold_button.dart';

import 'reading_test_support.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test(
    'share/review payloads and saved moderation state follow C3/C4',
    () async {
      final api = ParityApi()
        ..onPost = (call) => call.path.endsWith('/share')
            ? {
                'data': {
                  'public': true,
                  'url': 'https://xn--82c4af5bzdj.online/tarot/result/1',
                },
              }
            : {
                'data': {
                  'review': {
                    'rating': 4,
                    'message': 'ตรง',
                    'allow_public': true,
                    'approved': false,
                  },
                },
              };
      final repo = ReadingEngagementRepository(api);
      expect((await repo.setShare(1, public: true)).public, isTrue);
      final review = await repo.saveReview(
        1,
        rating: 4,
        message: ' ตรง ',
        allowPublic: true,
      );
      expect(review.approved, isFalse);
      expect(api.calls[0].data, {'public': true});
      expect(api.calls[1].data, {
        'rating': 4,
        'message': 'ตรง',
        'allow_public': true,
      });
    },
  );

  test(
    'only explicit wait 409 is pollable; other conflicts remain errors',
    () async {
      final api = ParityApi()
        ..onPost = (_) => throw ApiException(
          statusCode: 409,
          message: 'รอ',
          body: {
            'data': {'wait': true, 'status': 'building'},
          },
        );
      final repo = ReadingEngagementRepository(api);
      expect((await repo.voiceNext(1)).wait, isTrue);
      api.onPost = (_) => throw ApiException(
        statusCode: 409,
        message: 'ไม่พร้อม',
        body: {'reason_code': 'unavailable'},
      );
      await expectLater(repo.voiceNext(1), throwsA(isA<ApiException>()));
    },
  );

  Future<void> mount(WidgetTester tester, ParityApi api, Widget child) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          readingEngagementRepositoryProvider.overrideWith(
            (ref) async => ReadingEngagementRepository(api),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'review needs stars, blocks double submit, preserves validation and shows saved result',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      final api = ParityApi()..onPost = (_) => pending.future;
      await mount(tester, api, const ReadingReviewCard(readingId: 1));
      expect(
        tester.widget<GoldButton>(find.byType(GoldButton)).disabled,
        isTrue,
      );
      await tester.tap(find.bySemanticsLabel('4 ดาว'));
      await tester.enterText(find.byType(TextField), 'ตรงใจ');
      await tester.ensureVisible(find.text('ส่งรีวิว'));
      await tester.tap(find.text('ส่งรีวิว'));
      await tester.pump();
      await tester.tap(find.byType(GoldButton));
      expect(api.calls, hasLength(1));
      pending.completeError(
        ApiException(statusCode: 422, message: 'ข้อความยาวเกินไปค่ะ'),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('ข้อความยาวเกินไปค่ะ'), findsOneWidget);
      api.onPost = (_) => {
        'data': {
          'review': {'rating': 4, 'message': 'ตรงใจ', 'allow_public': false},
        },
      };
      await tester.ensureVisible(find.text('ส่งรีวิว'));
      await tester.tap(find.text('ส่งรีวิว'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('แก้รีวิว'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets(
    'review 404 hides unavailable control; disposal ignores late result',
    (tester) async {
      final api = ParityApi()
        ..onPost = (_) =>
            throw ApiException(statusCode: 404, message: 'Not found');
      await mount(tester, api, const ReadingReviewCard(readingId: 1));
      await tester.tap(find.bySemanticsLabel('5 ดาว'));
      await tester.pump();
      await tester.ensureVisible(find.text('ส่งรีวิว'));
      await tester.tap(find.text('ส่งรีวิว'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(GoldButton), findsNothing);
      final pending = Completer<Map<String, dynamic>>();
      api.onPost = (_) => pending.future;
      await mount(
        tester,
        api,
        const ReadingReviewCard(key: ValueKey(2), readingId: 2),
      );
      await tester.tap(find.bySemanticsLabel('5 ดาว'));
      await tester.pump();
      await tester.ensureVisible(find.text('ส่งรีวิว'));
      await tester.tap(find.text('ส่งรีวิว'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      pending.complete({
        'data': {
          'review': {'rating': 5},
        },
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('voice 404 hides panel and does not schedule more requests', (
    tester,
  ) async {
    final api = ParityApi()
      ..onPost = (_) =>
          throw ApiException(statusCode: 404, message: 'Not found');
    await mount(
      tester,
      api,
      const ReadingVoicePanel(
        readingId: 1,
        premium: ReadingPremium(status: 'active'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 9));
    expect(api.calls, hasLength(1));
    expect(find.textContaining('พรีเมียม'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    expect(api.calls, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
