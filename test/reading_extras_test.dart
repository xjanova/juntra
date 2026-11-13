import 'package:flutter_test/flutter_test.dart';
import 'package:juntra/core/api/fortune_repository.dart';
import 'package:juntra/core/api/reading_engagement_repository.dart';

void main() {
  test('old reading keeps defaults without assuming premium or sharing', () {
    final extras = ReadingExtras.fromReading(const {
      'id': 1,
      'result': 'คำทำนาย',
    });
    expect(extras.readerDisplay, 'แม่หมอ');
    expect(extras.room, isNull);
    expect(extras.premium, isNull);
    expect(extras.review, isNull);
    expect(extras.share.public, isFalse);
    expect(extras.qaMinutes, isNull);
    expect(extras.voice, isNull);
    expect(extras.free, isFalse);
  });

  test('C2 parses room, premium, review, public link and follow-up clock', () {
    final extras = ReadingExtras.fromReading(const {
      'persona': 'busaba',
      'reader_name': 'น้องบุษบา',
      'room': {
        'key': 'busaba',
        'name': 'น้องบุษบา',
        'short': 'บุษบา',
        'image_url': 'https://example.com/room.webp',
      },
      'premium': {'status': 'active', 'price': '100'},
      'review': {'rating': 5, 'message': ' ตรงใจ ', 'allow_public': true},
      'share': {
        'public': true,
        'url': 'https://xn--82c4af5bzdj.online/tarot/result/1',
      },
      'qa_minutes': 20,
      'payload': {
        'free': true,
        'voice': {
          'status': 'partial',
          'duration': 12.5,
          'chapters': [
            {'start': 0, 'end': 12.5, 'say': 'คำทำนาย'},
          ],
        },
      },
    });
    expect(extras.persona, 'busaba');
    expect(extras.readerDisplay, 'น้องบุษบา');
    expect(extras.readerShort, 'บุษบา');
    expect(extras.room!.imageUrl, startsWith('https://'));
    expect(extras.premium!.active, isTrue);
    expect(extras.premium!.price, 100);
    expect(extras.review!.rating, 5);
    expect(extras.review!.message, 'ตรงใจ');
    expect(extras.review!.allowPublic, isTrue);
    expect(extras.share.public, isTrue);
    expect(extras.qaMinutes, 20);
    expect(extras.voice!.playable, isTrue);
    expect(extras.voice!.chapters.single.end, 12.5);
    expect(extras.free, isTrue);
  });

  test('legacy paid/refunded payload and invalid room art are safe', () {
    final extras = ReadingExtras.fromReading(const {
      'room': {'image_url': 'javascript:x'},
      'payload': {
        'premium': {'status': 'refunded'},
      },
    });
    expect(extras.room!.imageUrl, isNull);
    expect(extras.premium!.refunded, isTrue);
    expect(ReadingPremium.fromJson(const {'status': 'paid'}).active, isTrue);
    expect(
      ReadingExtras.fromReading(const {'qa_minutes': 0}).qaMinutes,
      isNull,
    );
  });

  test('voice progress handles waiting, partial audio and refunds', () {
    final built = VoiceBuild.fromJson(const {
      'status': 'ready',
      'voice': {
        'status': 'ready',
        'url':
            'https://xn--82c4af5bzdj.online/api/v1/history/readings/1/voice.mp3',
      },
    });
    expect(built.url, endsWith('/1/voice.mp3'));
    expect(
      VoiceBuild.fromJson(const {
        'status': 'building',
        'done': 5,
        'total': 3,
      }).progress,
      1,
    );
    expect(VoiceBuild.fromJson(const {'wait': true}).wait, isTrue);
    expect(VoiceBuild.fromJson(const {'status': 'partial'}).ready, isTrue);
    expect(
      VoiceBuild.fromJson(const {'status': 'none', 'refunded': true}).refunded,
      isTrue,
    );
  });
}
