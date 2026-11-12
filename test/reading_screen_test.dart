import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:juntra/core/api/app_config_repository.dart';
import 'package:juntra/core/api/fortune_repository.dart';
import 'package:juntra/core/api/free_card_repository.dart';
import 'package:juntra/core/auth/session.dart';
import 'package:juntra/features/reading/reading_aftercare.dart';
import 'package:juntra/features/reading/reading_screen.dart';
import 'package:juntra/features/reading/reading_voice_panel.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> mount(
    WidgetTester tester, {
    String type = 'tarot_single',
    String status = 'done',
    bool features = true,
    int? conversation,
  }) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const ReadingScreen(readingId: 1),
        ),
        GoRoute(
          path: '/chat',
          builder: (_, state) => Scaffold(body: Text('chat ${state.uri}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWithValue('a'),
          appConfigValueProvider.overrideWithValue(
            AppConfig(
              services: const {'tarot': true, 'chat': true},
              features: {'reading_share': features, 'reading_review': features},
            ),
          ),
          freeCardConversationsProvider.overrideWith(
            (ref) => {1: ?conversation},
          ),
          readingDetailProvider(1).overrideWith(
            (ref) async => {
              'id': 1,
              'type': type,
              'status': status,
              'result': 'คำทำนาย',
              'reader_name': 'น้องบุษบา',
              'premium': {'status': 'active'},
              'qa_minutes': 7,
            },
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'old-server feature flags hide review, share control and premium narration',
    (tester) async {
      await mount(tester, features: false);
      expect(find.byType(ReadingReviewCard), findsNothing);
      expect(find.byType(ReadingShareCard), findsNothing);
      expect(find.byType(ReadingVoicePanel), findsNothing);
      expect(find.textContaining('คุยต่อกับน้องบุษบา'), findsOneWidget);
    },
  );

  testWidgets(
    'non-tarot and failed results never expose share/review endpoints',
    (tester) async {
      await mount(tester, type: 'deep');
      expect(find.byType(ReadingReviewCard), findsNothing);
      expect(find.byType(ReadingShareCard), findsNothing);
      expect(find.byIcon(Icons.share_outlined), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await mount(tester, status: 'failed');
      expect(find.byType(ReadingReviewCard), findsNothing);
      expect(find.byType(ReadingShareCard), findsNothing);
      expect(find.byIcon(Icons.share_outlined), findsNothing);
    },
  );

  testWidgets(
    'free reading CTA resumes returned conversation, paid reading uses reading context',
    (tester) async {
      await mount(tester, conversation: 25);
      await tester.ensureVisible(find.text('คุยต่อกับน้องบุษบา'));
      await tester.tap(find.text('คุยต่อกับน้องบุษบา'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('chat /chat?id=25'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await mount(tester);
      await tester.ensureVisible(find.text('คุยต่อกับน้องบุษบา'));
      await tester.tap(find.text('คุยต่อกับน้องบุษบา'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('chat /chat?reading=1'), findsOneWidget);
    },
  );
}
