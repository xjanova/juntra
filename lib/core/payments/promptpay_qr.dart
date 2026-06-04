/// EMVCo-compliant PromptPay QR payload builder.
///
/// Turns a PromptPay proxy id (mobile number / 13-digit national id /
/// 15-digit e-wallet id) into the exact string a Thai banking app expects
/// when it scans a "QR พร้อมเพย์". This lets a user **scan to pay** instead
/// of hand-typing the receiver id — which is what the wallet top-up sheet
/// asked them to do before.
///
/// Pure Dart, no network, no secrets. Reference: *EMV QR Code Specification
/// for Payment Systems (Merchant-Presented Mode) v1.1* + Bank of Thailand
/// PromptPay addendum (AID `A000000677010111`).
library;

import 'package:flutter/foundation.dart';

/// Result of normalizing a raw proxy id into a PromptPay merchant sub-tag.
class _Target {
  const _Target(this.tag, this.value);

  /// Sub-tag inside the tag-29 merchant TLV: `01` mobile, `02` national id,
  /// `03` e-wallet id.
  final String tag;

  /// The normalized, digit-only value as it must appear in the payload.
  final String value;
}

class PromptPayQr {
  PromptPayQr._();

  /// Build the QR payload for [proxyId]. When [amount] is non-null and > 0
  /// the QR is *dynamic* (the bank app pre-fills the amount and the QR is a
  /// one-shot); otherwise it's *static* (re-usable, user types the amount).
  ///
  /// Returns `null` when [proxyId] can't be normalized to a valid PromptPay
  /// target — callers should then fall back to showing the id as text.
  static String? build({required String proxyId, double? amount}) {
    final target = _normalizeTarget(proxyId);
    if (target == null) return null;

    final isDynamic = amount != null && amount > 0;

    final sb = StringBuffer()
      ..write(_field('00', '01')) // payload format indicator
      ..write(_field('01', isDynamic ? '12' : '11')); // point-of-init method

    // Tag 29 — Merchant Account Information (PromptPay): AID + proxy sub-tag.
    final merchant =
        '${_field('00', 'A000000677010111')}'
        '${_field(target.tag, target.value)}';
    sb
      ..write(_field('29', merchant))
      ..write(_field('53', '764')); // transaction currency — THB (ISO 4217)

    // Direct null-check (not `isDynamic`) so `amount` promotes to non-null
    // here on every SDK, without relying on boolean-flag promotion.
    if (amount != null && amount > 0) {
      sb.write(_field('54', amount.toStringAsFixed(2))); // amount — dynamic QR
    }
    sb.write(_field('58', 'TH')); // country code

    // Tag 63 — CRC. The checksum is computed over the entire payload built
    // so far *plus* the literal "6304" id+length of the CRC field itself.
    final crc = _crc16Ccitt('${sb.toString()}6304');
    sb.write('6304$crc');

    return sb.toString();
  }

  /// `id || len(2) || value` — the EMVCo TLV primitive. Values longer than
  /// 99 chars can't be length-prefixed in 2 digits; PromptPay never needs
  /// that, so we assert against it in debug to catch a malformed caller.
  static String _field(String id, String value) {
    assert(value.length <= 99, 'EMVCo field "$id" too long: ${value.length}');
    final len = value.length.toString().padLeft(2, '0');
    return '$id$len$value';
  }

  /// Normalize a human-entered / backend-supplied proxy id to the digit form
  /// PromptPay encodes. Strips spaces, dashes and a leading `+`.
  static _Target? _normalizeTarget(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;

    // e-Wallet id (15 digits) and national/tax id (13 digits) go in verbatim.
    if (digits.length == 15) return _Target('03', digits);
    if (digits.length == 13) return _Target('02', digits);

    // Mobile: encoded as 0066 + 9-digit subscriber number (leading 0 dropped),
    // i.e. a 13-char value. Accept the common shapes a user/backend may hold.
    if (digits.length == 10 && digits.startsWith('0')) {
      return _Target('01', '0066${digits.substring(1)}');
    }
    if (digits.length == 11 && digits.startsWith('66')) {
      return _Target('01', '00$digits'); // 66 + 9 subscriber digits
    }
    if (digits.length == 9) {
      return _Target('01', '0066$digits'); // bare subscriber number
    }
    return null;
  }

  /// CRC-16/CCITT-FALSE: poly 0x1021, init 0xFFFF, no reflection, no final
  /// xor — the variant EMVCo / PromptPay mandate. Returns 4 upper-case hex
  /// chars (zero-padded).
  ///
  /// Exposed for tests so the checksum can be pinned against the canonical
  /// CRC-16/CCITT-FALSE check value (`"123456789"` → `29B1`) independently
  /// of the rest of the payload builder.
  @visibleForTesting
  static String crc16ForTesting(String data) => _crc16Ccitt(data);

  static String _crc16Ccitt(String data) {
    var crc = 0xFFFF;
    for (final byte in data.codeUnits) {
      crc ^= byte << 8;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1;
        crc &= 0xFFFF;
      }
    }
    return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
  }
}
