import 'package:flutter_test/flutter_test.dart';
import 'package:juntra/core/api/chat_repository.dart';
import 'package:juntra/core/api/rooms_repository.dart';
import 'package:juntra/core/api/tarot_packages_repository.dart';
import 'package:juntra/core/voice/media_url.dart';
import 'package:juntra/features/chat/room_packages.dart';

void main() {
  final received = DateTime.fromMillisecondsSinceEpoch(1000000);

  test('old server conversation remains maemor without clocks or bills', () {
    final c = ChatStart.fromJson(const {
      'conversation': {'id': 12},
      'cost': 2,
    }, receivedAt: received).conversation;
    expect(c.id, 12);
    expect(c.room.key, 'maemor');
    expect(c.personaKnown, isFalse);
    expect(c.status.qa, isNull);
    expect(c.status.freeAsk, isNull);
    expect(c.status.pendingBill, isNull);
    expect(c.quota.cost, 2);
  });

  test('start envelope combines persona, clocks and outer quota', () {
    final c = ChatStart.fromJson(const {
      'conversation': {
        'id': 13,
        'persona': 'busaba',
        'room': {'key': 'busaba', 'name': 'น้องบุษบา'},
      },
      'qa': {'minutes': 7, 'started': true, 'ends_at': 1160, 'left': 60},
      'server_time': 1100,
      'daily_limit': null,
      'next_cost': 3,
    }, receivedAt: received).conversation;
    expect(c.room.key, 'busaba');
    expect(c.room.name, 'น้องบุษบา');
    expect(c.personaKnown, isTrue);
    expect(c.status.qa!.secondsLeft(received), 60);
    expect(c.quota.dailyLimit, isNull);
    expect(c.quota.nextCost, 3);
  });

  test('server clock skew, warning and expiry ignore wrong device time', () {
    final s = ChatRoomStatus.fromJson(const {
      'server_time': 2000,
      'qa': {
        'minutes': 7,
        'started': true,
        'ends_at': 2061,
        'warn': 1,
        'premium': true,
      },
    }, receivedAt: received);
    final c = s.qa!;
    expect(c.secondsLeft(received), 61);
    expect(c.isLow(now: received), isFalse);
    expect(c.isLow(now: received.add(const Duration(seconds: 1))), isTrue);
    expect(c.isOver(received.add(const Duration(seconds: 61))), isTrue);
    expect(c.premium, isTrue);
  });

  test('unstarted clocks stay idle and ended clocks are over', () {
    final idle = ChatClock.fromJson({
      'minutes': 2,
      'started': false,
      'left': 120,
    })!;
    expect(idle.secondsLeft(received), 120);
    expect(idle.isLow(now: received), isFalse);
    expect(
      ChatClock.fromJson({'minutes': 2, 'ended': true})!.isOver(received),
      isTrue,
    );
    expect(ChatClock.format(-10), '00:00');
    expect(ChatClock.format(3661), '1:01:01');
  });

  test('staff label only for explicit staff, including feed messages', () {
    final feed = ChatFeed.fromJson(const {
      'data': [
        {
          'id': 4,
          'role': 'assistant',
          'content': 'สวัสดี',
          'admin_as': 'admin',
        },
        {'id': 5, 'role': 'assistant', 'content': 'ค่ะ', 'admin_as': null},
        {'id': 6, 'role': 'assistant', 'content': 'ค่ะ', 'from_admin': true},
        {'id': 7, 'role': 'user', 'content': 'คุณ', 'from_admin': true},
      ],
      'meta': {'held': true},
    });
    expect(feed.held, isTrue);
    expect(feed.messages.map((m) => m.isStaff), [true, false, true, false]);
  });

  test('held has no fabricated message; degraded preserves retry reply', () {
    final held = ChatSendResult.fromJson(const {
      'kind': 'held',
      'message': null,
      'reply': 'ข้อความสำหรับแอพเก่า',
    }, receivedAt: received);
    expect(held.held, isTrue);
    expect(held.message, isNull);
    final degraded = ChatSendResult.fromJson(const {
      'degraded': true,
      'message': null,
      'reply': 'ลองใหม่ค่ะ',
    }, receivedAt: received);
    expect(degraded.degraded, isTrue);
    expect(degraded.reply, 'ลองใหม่ค่ะ');
  });

  test('offers keep Thai date locks; deep is encoded as spread', () {
    final offers = ChatOffer.listFrom([
      {
        'spread': 'love',
        'key': 'love',
        'label': 'ความรัก',
        'locked_until': '13 พ.ย. 2569',
        'price': '39.5',
      },
      {
        'spread': 'deep',
        'key': 'deep',
        'label': 'เจาะลึก',
        'locked_until': null,
      },
    ]);
    expect(offers.first.locked, isTrue);
    expect(offers.first.lockedUntil, '13 พ.ย. 2569');
    expect(offers.first.price, 39.5);
    expect(offers.last.kind, 'deep');
    expect(offers.last.locked, isFalse);
  });

  test('AI suggestions preserve explicit empty list to clear stale chips', () {
    expect(ChatQuota.fromJson(const {}).aiSuggestions, isNull);
    expect(ChatQuota.fromJson(const {'ai_suggestions': []}).aiSuggestions, isEmpty);
    expect(
      ChatQuota.fromJson(const {
        'ai_suggestions': [' คำถามใหม่ ', '', 4],
      }).aiSuggestions,
      ['คำถามใหม่'],
    );
  });

  test('pending bills preserve satang, has_slip and server expiry', () {
    final status = ChatRoomStatus.fromJson(const {
      'server_time': 1100,
      'pending_bill': {
        'id': 7,
        'ref': 'R7',
        'amount': 100,
        'payable_amount': 100.37,
        'expires_at': 1160,
        'has_slip': true,
        'blocks': true,
        'qr_payload': '000201',
      },
    }, receivedAt: received);
    final bill = status.pendingBill!;
    expect(bill.payableAmount, 100.37);
    expect(bill.hasSlip, isTrue);
    expect(bill.blocks, isTrue);
    expect(bill.secondsLeft(received), 60);
    expect(bill.isExpired(received.add(const Duration(minutes: 1))), isTrue);
  });

  test('qa end repeat has no second farewell', () {
    final first = ChatQaEndResult.fromJson(const {
      'qa': {'minutes': 7, 'over': true},
      'message': {'id': 20, 'role': 'assistant', 'content': 'ขอบคุณค่ะ'},
    }, receivedAt: received);
    final repeat = ChatQaEndResult.fromJson(const {
      'qa': {'minutes': 7, 'over': true},
      'message': null,
    }, receivedAt: received);
    expect(first.message!.id, 20);
    expect(repeat.message, isNull);
    expect(repeat.qa!.isOver(received), isTrue);
  });

  test('reply voice accepts only HTTPS and survives resumed messages', () {
    expect(
      ChatSendResult.fromJson(const {
        'reply_voice': {'url': 'http://invalid/a.mp3'},
      }, receivedAt: received).replyVoiceUrl,
      isNull,
    );
    expect(
      ChatMessageDto.fromJson({
        'reply_voice': {'url': 'https://cdn.example/a.mp3'},
      })!.replyVoiceUrl,
      'https://cdn.example/a.mp3',
    );
    expect(
      mediaUrl('https://จันทรา.online/a.mp3'),
      'https://xn--82c4af5bzdj.online/a.mp3',
    );
  });

  test(
    'room menu follows own spread first, without duplicates or removed products',
    () {
      final room = OracleRoom.fromJson(const {
        'key': 'busaba',
        'spreads': ['love', 'quick', 'removed'],
        'product': {'spread': 'quick', 'name': 'ดูไว', 'cards': 3, 'price': 39},
      });
      final all = [
        for (final key in ['love', 'quick', 'kunsai'])
          TarotPackage.fromJson({'key': key, 'name_th': key, 'cards': 3}),
      ];
      expect(roomPackages(room, all).map((p) => p.key), ['quick', 'love']);
    },
  );
}
