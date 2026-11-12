import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:juntra/core/api/api_client.dart';
import 'package:juntra/core/api/api_exceptions.dart';
import 'package:juntra/core/api/app_config_repository.dart';
import 'package:juntra/core/api/chat_repository.dart';
import 'package:juntra/core/api/rooms_repository.dart';
import 'package:juntra/core/app_channel.dart';
import 'package:juntra/core/auth/auth_state.dart';
import 'package:juntra/features/chat/chat_screen.dart';
import 'package:juntra/features/chat/chat_topup_sheet.dart';
import 'package:juntra/features/chat/conversation_list_screen.dart';
import 'package:juntra/features/chat/rooms_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends AuthController {
  _Auth(super.ref) {
    state = const AuthAuthenticated(userId: 'one', displayName: 'คุณ');
  }
  void switchTo(String id) =>
      state = AuthAuthenticated(userId: id, displayName: 'คุณ');
  @override
  Future<void> refresh() async {}
}

class _Repo extends ChatRepository {
  _Repo(super.api);
  final starts = <Map<String, Object?>>[];
  final keys = <String>[];
  final filters = <String?>[];
  int feeds = 0;
  int ends = 0;
  bool busy = false;
  bool held = false;
  bool feed404 = false;
  bool old = false;
  bool qaOver = false;
  bool voice = false;
  Completer<ChatSendResult>? sending;
  Completer<ChatStart>? starting;
  Completer<ChatQaEndResult>? ending;
  Map<String, dynamic> payload() => {
    'id': 10,
    if (!old) 'persona': 'busaba',
    'held': held,
    'qa': {'minutes': 7, 'started': false},
    'free_ask': {'minutes': 2, 'started': false},
    'pending_bill': {
      'id': 3,
      'amount': 100,
      'payable_amount': 100.37,
      'qr_payload': 'bill-secret',
      'blocks': true,
    },
    'messages': [
      {
        'id': 1,
        'role': 'assistant',
        'content': 'ยินดีค่ะ',
        if (voice) 'reply_voice': {'url': 'https://cdn.example/reply.mp3'},
      },
    ],
  };
  @override
  Future<ChatStart> startConversation({
    int? readingId,
    String? room,
    bool startNew = false,
  }) async {
    starts.add({'reading': readingId, 'room': room, 'new': startNew});
    return starting?.future ??
        ChatStart.fromJson({
          'conversation': payload(),
        }, receivedAt: DateTime.now());
  }

  @override
  Future<ChatConversation> getConversation(int id) async =>
      ChatConversation.fromJson(payload(), receivedAt: DateTime.now());
  @override
  Future<List<ChatConversationSummary>> listConversations({
    String? room,
  }) async {
    filters.add(room);
    return [
      ChatConversationSummary.fromJson({'id': 10, 'persona': room ?? 'busaba'}),
    ];
  }

  @override
  Future<ChatSendResult> send({
    required int conversationId,
    required String text,
    required String idempotencyKey,
  }) async {
    keys.add(idempotencyKey);
    if (busy) {
      throw ApiException(
        statusCode: 409,
        message: 'ส่งจากอีกเครื่องอยู่ ลองส่งใหม่อีกครั้ง',
        reasonCode: 'busy_other',
      );
    }
    if (qaOver) {
      throw ApiException(
        statusCode: 409,
        message: 'หมดเวลาถามต่อแล้วค่ะ',
        reasonCode: 'qa_over',
      );
    }
    return sending?.future ??
        ChatSendResult.fromJson({
          'kind': held ? 'held' : 'reply',
          'reply': held ? 'แม่หมอกำลังพักสายตา' : 'คำตอบใหม่',
          'message': held ? null : {'id': 2, 'content': 'คำตอบใหม่'},
        }, receivedAt: DateTime.now());
  }

  @override
  Future<ChatFeed> feed(int conversationId, {required int after}) async {
    feeds++;
    if (feed404) {
      throw ApiException(statusCode: 404, message: 'ยังไม่เปิดบริการ');
    }
    return const ChatFeed(
      messages: [
        ChatMessageDto(
          id: 3,
          role: 'assistant',
          content: 'เจ้าหน้าที่ตอบแล้ว',
          adminAs: 'admin',
        ),
      ],
      held: false,
    );
  }

  @override
  Future<ChatQaEndResult> qaEnd(int conversationId) async {
    ends++;
    return ending?.future ?? const ChatQaEndResult();
  }
}

/// Flutter อนุญาตเฉพาะการเปลี่ยนสถานะทีละขั้น (resumed ↔ inactive ↔ hidden ↔ paused)
void _lifecycle(WidgetTester tester, {required bool foreground}) {
  final steps = foreground
      ? const [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]
      : const [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ];
  for (final s in steps) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Repo repo;
  late ApiClient api;
  late _Auth auth;
  late GoRouter router;
  late AppConfig config;
  String? destination;
  final rooms = RoomsState.fromJson(const {
    'data': [
      {'key': 'busaba', 'open': true},
      {'key': 'maemor', 'open': true},
      {'key': 'kunsai', 'open': false},
    ],
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    api = await ApiClient.create();
    repo = _Repo(api);
    config = AppConfig.fromJson(const {
      'features': {
        'rooms': true,
        'qa_clock': true,
        'free_ask': true,
        'chat_feed': true,
      },
    });
    destination = null;
  });
  tearDown(() {
    router.dispose();
    api.dio.close(force: true);
  });

  Future<void> show(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(500, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => screen),
        for (final path in ['/rooms', '/chat', '/login', '/home'])
          GoRoute(
            path: path,
          builder: (_, state) {
            destination = state.uri.toString();
            return const Scaffold(body: Text('destination'));
          },
          ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // AuthController bootstrap waits here; no platform/network login in UI tests.
          apiClientProvider.overrideWith((_) => Completer<ApiClient>().future),
          authControllerProvider.overrideWith((ref) => auth = _Auth(ref)),
          chatRepositoryProvider.overrideWith((_) async => repo),
          appConfigProvider.overrideWith((_) async => config),
          roomsProvider.overrideWith((_) async => rooms),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('list filters query by room and FAB follows selected room', (
    tester,
  ) async {
    await show(tester, const ConversationListScreen());
    expect(find.byType(ChoiceChip), findsNWidgets(4));
    await tester.tap(find.widgetWithText(ChoiceChip, 'บุษบา'));
    await tester.pump();
    await tester.pump();
    expect(repo.filters.last, 'busaba');
    expect(find.text('สนทนากับน้องบุษบา'), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    expect(
      destination,
      '/chat?room=busaba&new=1',
    );
  });

  testWidgets('unfiltered FAB opens rooms; old server hides room filter', (
    tester,
  ) async {
    await show(tester, const ConversationListScreen());
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    expect(destination, '/rooms');
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    config = AppConfig.fallback;
    await show(tester, const ConversationListScreen());
    expect(find.byType(ChoiceChip), findsNothing);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    expect(
      destination,
      '/chat?room=maemor&new=1',
    );
  });

  testWidgets(
    'old config hides clocks and payment UI even if API sends fields',
    (tester) async {
      config = AppConfig.fallback;
      repo.old = true;
      await show(tester, const ChatScreen(room: 'busaba', startNew: true));
      expect(repo.starts.single['room'], isNull);
      expect(find.textContaining('ถามต่อได้'), findsNothing);
      expect(find.textContaining('บิลเลขที่'), findsNothing);
      expect(find.text('ดู QR จ่ายต่อ'), findsNothing);
      expect(find.text('แม่หมอจันทรา'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    },
  );

  testWidgets('busy_other UI retry keeps key; double send is ignored', (
    tester,
  ) async {
    repo.busy = true;
    await show(tester, const ChatScreen(room: 'busaba'));
    await tester.enterText(find.byType(TextField), 'คำถามของคุณ');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('ส่งจากอีกเครื่องอยู่ ลองส่งใหม่อีกครั้ง'),
      findsOneWidget,
    );
    repo.busy = false;
    repo.sending = Completer<ChatSendResult>();
    await tester.tap(find.text('ลองส่งใหม่'));
    await tester.pump();
    expect(repo.keys, hasLength(2));
    expect(repo.keys[0], repo.keys[1]);
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(repo.keys, hasLength(2));
    repo.sending!.complete(
      ChatSendResult.fromJson(const {
        'reply': 'จบ',
        'message': {'id': 2, 'content': 'จบ'},
      }, receivedAt: DateTime.now()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('held polls staff feed without canned oracle bubble', (
    tester,
  ) async {
    repo.held = true;
    await show(tester, const ChatScreen(room: 'busaba'));
    expect(find.textContaining('พักสายตา'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(repo.feeds, 1);
    expect(find.text('เจ้าหน้าที่'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    expect(repo.feeds, 1);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('feed 404 stops; leaving during bootstrap discards response', (
    tester,
  ) async {
    repo.held = true;
    repo.feed404 = true;
    await show(tester, const ChatScreen(room: 'busaba'));
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    await tester.pump(const Duration(seconds: 12));
    expect(repo.feeds, 1);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    repo.starting = Completer<ChatStart>();
    await show(tester, const ChatScreen(room: 'busaba'));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    repo.starting!.complete(
      ChatStart.fromJson({
        'conversation': repo.payload(),
      }, receivedAt: DateTime.now()),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('qa end requires confirmation and cannot double submit', (
    tester,
  ) async {
    repo.ending = Completer<ChatQaEndResult>();
    await show(tester, const ChatScreen(room: 'busaba'));
    await tester.tap(find.text('พอแล้ว'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(repo.ends, 0);
    await tester.tap(find.widgetWithText(TextButton, 'พอแล้ว'));
    await tester.pump();
    expect(repo.ends, 1);
    repo.ending!.complete(
      ChatQaEndResult.fromJson(const {
        'qa': {'minutes': 7, 'over': true},
        'message': null,
      }, receivedAt: DateTime.now()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(find.textContaining('คุยเรื่องอื่นกับ'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('account switch replaces previous user conversation', (
    tester,
  ) async {
    repo.starting = Completer<ChatStart>();
    await show(tester, const ChatScreen(room: 'busaba'));
    final stale = repo.starting!;
    repo.starting = null;
    auth.switchTo('two');
    await tester.pump();
    await tester.pump();
    stale.complete(
      ChatStart.fromJson(const {
        'conversation': {
          'id': 99,
          'messages': [
            {'content': 'private old user'},
          ],
        },
      }, receivedAt: DateTime.now()),
    );
    await tester.pump();
    expect(find.text('private old user'), findsNothing);
    expect(repo.starts, hasLength(2));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('Play blocks topup sheet even through direct construction', (
    tester,
  ) async {
    await show(tester, const ChatTopUpSheet());
    expect(find.textContaining('สแกน'), findsNothing);
    final context = tester.element(find.byType(ChatTopUpSheet));
    expect(await ChatTopUpSheet.show(context), isFalse);
  }, skip: !isPlayChannel);

  testWidgets('pending bill shows only on the APK channel, never on Play', (
    tester,
  ) async {
    await show(tester, const ChatScreen(room: 'busaba'));
    // Play: เซิร์ฟเวอร์ส่งบิลมาผิด ๆ ก็ต้องไม่เห็นอะไรเกี่ยวกับพร้อมเพย์
    expect(
      find.text('ดู QR จ่ายต่อ'),
      isPlayChannel ? findsNothing : findsOneWidget,
    );
    expect(
      find.textContaining('บิลเลขที่'),
      isPlayChannel ? findsNothing : findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('reply voice button only when server has voice_premium', (
    tester,
  ) async {
    repo.voice = true;
    await show(tester, const ChatScreen(room: 'busaba'));
    expect(find.text('ฟังเสียง'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    router.dispose();
    config = AppConfig.fromJson(const {
      'features': {'rooms': true, 'voice_premium': true},
    });
    await show(tester, const ChatScreen(room: 'busaba'));
    expect(find.text('ฟังเสียง'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('double tap on new-chat FAB pushes one page, not two', (
    tester,
  ) async {
    await show(tester, const ConversationListScreen());
    final fab = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    fab.onPressed!();
    await tester.pump();
    // แตะครั้งที่สองมาหลังเฟรมแรก (แตะสองทีจริงห่างกันหลายเฟรม)
    fab.onPressed!();
    await tester.pump();
    expect(router.routerDelegate.currentConfiguration.matches, hasLength(2));
    expect(destination, '/rooms');
  });

  testWidgets('rooms on old config redirect without calling new endpoint', (
    tester,
  ) async {
    config = AppConfig.fallback;
    await show(tester, const RoomsScreen());
    await tester.pump();
    expect(
      destination,
      '/chat?room=maemor',
    );
  });

  testWidgets('qa_over without qa object still disables composer', (tester) async {
    repo.qaOver = true;
    await show(tester, const ChatScreen(room: 'busaba'));
    await tester.enterText(find.byType(TextField), 'คำถาม');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(find.text('หมดเวลาถามต่อแล้วค่ะ'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('feed pauses in background and respects missing feature flag', (tester) async {
    repo.held = true;
    await show(tester, const ChatScreen(room: 'busaba'));
    _lifecycle(tester, foreground: false);
    await tester.pump(const Duration(seconds: 12));
    expect(repo.feeds, 0);
    _lifecycle(tester, foreground: true);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(repo.feeds, 1);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    config = AppConfig.fromJson(const {'features': {'rooms': true}});
    await show(tester, const ChatScreen(room: 'busaba'));
    await tester.pump(const Duration(seconds: 12));
    expect(repo.feeds, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
