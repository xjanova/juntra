import 'package:flutter_test/flutter_test.dart';
import 'package:juntra/core/payments/promptpay_qr.dart';

/// Recompute the CRC over the payload minus its trailing 4 hex chars and
/// confirm it matches — proves the emitted checksum is internally valid.
String _trailingCrc(String payload) => payload.substring(payload.length - 4);
String _bodyWithCrcTag(String payload) =>
    payload.substring(0, payload.length - 4); // already includes "6304"

void main() {
  group('CRC-16/CCITT-FALSE', () {
    test('matches the canonical check value', () {
      // Standard catalogue check: ASCII "123456789" → 0x29B1.
      expect(PromptPayQr.crc16ForTesting('123456789'), '29B1');
    });
  });

  group('PromptPay payload — mobile', () {
    test('dynamic QR (with amount) is well-formed', () {
      final qr = PromptPayQr.build(proxyId: '0899999999', amount: 4.22)!;

      expect(qr.startsWith('000201'), isTrue); // payload format
      expect(qr.contains('010212'), isTrue); // POI = dynamic
      expect(qr.contains('A000000677010111'), isTrue); // PromptPay AID
      expect(qr.contains('0066899999999'), isTrue); // 0 → 0066, leading 0 dropped
      expect(qr.contains('5303764'), isTrue); // currency THB
      expect(qr.contains('54044.22'), isTrue); // amount, 2dp
      expect(qr.contains('5802TH'), isTrue); // country

      // CRC self-consistency: recomputing over body+"6304" reproduces the tail.
      expect(PromptPayQr.crc16ForTesting(_bodyWithCrcTag(qr)), _trailingCrc(qr));
    });

    test('static QR (no amount) omits tag 54 and flags POI 11', () {
      final qr = PromptPayQr.build(proxyId: '081-234-5678')!;
      expect(qr.contains('010211'), isTrue); // POI = static
      expect(qr.contains('5303764'), isTrue);
      expect(qr.contains('5402'), isFalse); // no amount field
      expect(qr.contains('0066812345678'), isTrue); // dashes stripped
    });

    test('amount <= 0 is treated as static', () {
      final qr = PromptPayQr.build(proxyId: '0899999999', amount: 0)!;
      expect(qr.contains('010211'), isTrue);
      expect(qr.contains('5402'), isFalse);
    });
  });

  group('PromptPay payload — other proxy types', () {
    test('13-digit national id uses sub-tag 02', () {
      final qr = PromptPayQr.build(proxyId: '1234567890123', amount: 50)!;
      // tag29 → 00..AID.. then 02 13 <id>
      expect(qr.contains('02131234567890123'), isTrue);
    });

    test('15-digit e-wallet id uses sub-tag 03', () {
      final qr = PromptPayQr.build(proxyId: '123456789012345', amount: 50)!;
      expect(qr.contains('0315123456789012345'), isTrue);
    });
  });

  group('PromptPay payload — invalid input', () {
    test('returns null for un-normalizable ids', () {
      expect(PromptPayQr.build(proxyId: ''), isNull);
      expect(PromptPayQr.build(proxyId: 'not-a-number'), isNull);
      expect(PromptPayQr.build(proxyId: '12345'), isNull); // wrong length
    });
  });
}
