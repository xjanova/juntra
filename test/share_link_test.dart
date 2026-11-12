import 'package:flutter_test/flutter_test.dart';
import 'package:juntra/core/api/fortune_repository.dart';
import 'package:juntra/features/share/share_link.dart';

void main() {
  test('private and old-server readings share text without broken links', () {
    expect(shareLinkFor(readingId: 12).hasUrl, isFalse);
    expect(
      shareLinkFor(
        readingId: 12,
        share: const ReadingShare(public: false, url: 'https://example.com'),
      ).hasUrl,
      isFalse,
    );
    expect(
      shareLinkFor(
        readingId: 12,
        share: const ReadingShare(public: true),
      ).hasUrl,
      isFalse,
    );
  });

  test(
    'only returned public result URL is shared, never GitHub or payment links',
    () {
      const url = '$kSiteUrl/tarot/result/12';
      final link = shareLinkFor(
        readingId: 12,
        share: const ReadingShare(public: true, url: url),
      );
      expect(link.url, url);
      expect(link.readingLink, isTrue);
      for (final bad in [
        'https://github.com/xjanova/juntra',
        '$kSiteUrl/wallet',
        '$kSiteUrl/tarot/result/13',
        'http://xn--82c4af5bzdj.online/tarot/result/12',
      ]) {
        expect(
          shareLinkFor(
            readingId: 12,
            share: ReadingShare(public: true, url: bad),
          ).hasUrl,
          isFalse,
        );
      }
      expect(
        shareMessage(readingId: 12, reader: 'น้องบุษบา'),
        contains('น้องบุษบา'),
      );
    },
  );
}
