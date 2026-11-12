import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juntra/core/api/api_client.dart';
import 'package:juntra/core/api/api_exceptions.dart';
import 'package:juntra/core/api/chat_repository.dart';

class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  int status = 200;
  Map<String, dynamic> response = {'data': <String, dynamic>{}};
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(response),
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
  late ApiClient api;
  late ChatRepository repo;
  late _Adapter adapter;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    api = await ApiClient.create();
    api.dio.interceptors.clear();
    adapter = _Adapter();
    api.dio.httpClientAdapter = adapter;
    repo = ChatRepository(api);
  });
  tearDown(() => api.dio.close(force: true));

  test('reading entry takes priority over room and new', () async {
    adapter.response = {
      'data': {
        'conversation': {'id': 1},
      },
    };
    await repo.startConversation(readingId: 42, room: 'busaba', startNew: true);
    expect(adapter.requests.single.data, {'reading_id': 42});
  });

  test(
    'room resume/new and old server request bodies remain additive',
    () async {
      adapter.response = {
        'data': {
          'conversation': {'id': 1, 'persona': 'busaba'},
        },
      };
      final first = await repo.startConversation(
        room: 'busaba',
        startNew: true,
      );
      expect(first.conversation.persona, 'busaba');
      expect(adapter.requests.last.data, {'room': 'busaba', 'new': true});
      await repo.startConversation(room: 'busaba');
      expect(adapter.requests.last.data, {'room': 'busaba'});
      await repo.startConversation();
      expect(adapter.requests.last.data, isNull);
    },
  );

  test('list filter, live envelope and feed cursor use the contract', () async {
    adapter.response = {
      'data': [
        {'id': 10, 'persona': 'kunsai', 'free_reading_id': 5},
      ],
    };
    final rows = await repo.listConversations(room: 'kunsai');
    expect(adapter.requests.last.queryParameters, {'room': 'kunsai'});
    expect(rows.single.room.key, 'kunsai');
    expect(rows.single.freeReadingId, 5);
    adapter.response = {
      'data': {'online': 17, 'refresh_seconds': 20},
    };
    expect((await repo.live()).online, 17);
    adapter.response = {
      'data': [
        {'id': 22, 'content': 'เจ้าหน้าที่ตอบแล้ว', 'admin_as': 'admin'},
      ],
      'meta': {'held': false},
    };
    expect((await repo.feed(10, after: 21)).messages.single.isStaff, isTrue);
    expect(adapter.requests.last.queryParameters, {'after': 21});
  });

  test(
    'busy_other retry sends exactly the same money idempotency key',
    () async {
      adapter.status = 409;
      adapter.response = {
        'message': 'ส่งจากอีกเครื่องอยู่ ลองส่งใหม่อีกครั้ง',
        'reason_code': 'busy_other',
      };
      await expectLater(
        repo.send(
          conversationId: 1,
          text: 'คำถาม',
          idempotencyKey: 'same-turn',
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.reasonCode,
            'reason',
            'busy_other',
          ),
        ),
      );
      adapter.status = 200;
      adapter.response = {
        'data': {
          'message': {'id': 2, 'content': 'คำตอบ'},
          'reply': 'คำตอบ',
        },
      };
      await repo.send(
        conversationId: 1,
        text: 'คำถาม',
        idempotencyKey: 'same-turn',
      );
      expect(adapter.requests.map((r) => r.headers['Idempotency-Key']), [
        'same-turn',
        'same-turn',
      ]);
      expect(adapter.requests.map((r) => r.data), [
        {'message': 'คำถาม'},
        {'message': 'คำถาม'},
      ]);
    },
  );

  test(
    'live badge: 404 = no service (hide), other failures stay errors (retry)',
    () async {
      final container = ProviderContainer(
        overrides: [chatRepositoryProvider.overrideWith((_) async => repo)],
      );
      addTearDown(container.dispose);
      final sub = container.listen(chatLiveStatsProvider, (_, _) {});
      addTearDown(sub.close);

      adapter.status = 404;
      adapter.response = {'message': 'ไม่พบบริการ'};
      expect(await container.read(chatLiveStatsProvider.future), isNull);

      adapter.status = 500;
      adapter.response = {'message': 'ระบบขัดข้อง'};
      container.invalidate(chatLiveStatsProvider);
      await expectLater(
        container.read(chatLiveStatsProvider.future),
        throwsA(isA<ApiException>()),
      );
    },
  );

  test(
    'new endpoint 404 keeps friendly API message and status for fallback',
    () async {
      adapter.status = 404;
      adapter.response = {'message': 'ยังไม่เปิดบริการนี้ค่ะ'};
      await expectLater(
        repo.feed(1, after: 0),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 404)
              .having((e) => e.message, 'message', 'ยังไม่เปิดบริการนี้ค่ะ'),
        ),
      );
    },
  );
}
