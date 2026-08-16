import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juntra/shared/data/juntra_art.dart';
import 'package:yaml/yaml.dart';

/// ภาพประกอบต้องมีอยู่จริง และต้องถูกประกาศใน pubspec
///
/// กับดักสองอันที่เทสต์ชุดนี้ดักไว้ ทั้งคู่ **ไม่มี error ให้เห็นตอน build**:
///
/// 1. `JuntraArt` ชี้ path ที่ไม่มีไฟล์ (พิมพ์ผิด / ลืมคัดลอกมา)
/// 2. ไฟล์มีจริงแต่ไม่ได้อยู่ในรายการ `assets:` ของ pubspec — Flutter
///    **ไม่ลงโฟลเดอร์ย่อยให้อัตโนมัติ** `assets/images/` จึงไม่กิน
///    `assets/images/art/` ภาพจะหายเงียบ ๆ ตอนรันจริง
///
/// ทั้งสองกรณี `errorBuilder` ของ [ArtBanner] จะกลืน error ไว้จนหน้าจอ
/// เหลือแค่ช่องว่าง — จับได้ตอนเปิดแอพด้วยตาเท่านั้น ถ้าไม่มีเทสต์นี้
void main() {
  /// รวม path ทุกเส้นที่ JuntraArt ประกาศไว้
  final declared = <String>[
    JuntraArt.tarot,
    JuntraArt.tarotFree,
    JuntraArt.horoscope,
    JuntraArt.thaiZodiac,
    JuntraArt.numerology,
    JuntraArt.palmistry,
    JuntraArt.auspicious,
    JuntraArt.deep,
    JuntraArt.chat,
    JuntraArt.wallet,
    JuntraArt.mlm,
    JuntraArt.account,
    JuntraArt.auth,
    JuntraArt.natal,
    JuntraArt.history,
    JuntraArt.share,
    JuntraArt.stateNoReading,
    JuntraArt.stateLocked,
    JuntraArt.divider,
    JuntraArt.frameThai,
    JuntraArt.nebula,
    JuntraArt.maeMor,
    JuntraArt.logo,
    ...JuntraArt.zodiacSlugs.map(JuntraArt.zodiac),
  ];

  test('ทุก path ใน JuntraArt มีไฟล์อยู่จริง', () {
    final missing = declared.where((p) => !File(p).existsSync()).toList();
    expect(missing, isEmpty, reason: 'ไฟล์ภาพหาย: ${missing.join(", ")}');
  });

  test('ราศีครบทั้ง 12 ใบ', () {
    expect(JuntraArt.zodiacSlugs, hasLength(12));
    for (final slug in JuntraArt.zodiacSlugs) {
      expect(File(JuntraArt.zodiac(slug)).existsSync(), isTrue,
          reason: 'ไม่มีภาพราศี $slug');
    }
  });

  test('ทุกโฟลเดอร์ที่ใช้ ถูกประกาศใน pubspec assets', () {
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync());
    final assets = (pubspec['flutter']['assets'] as YamlList)
        .map((e) => e.toString())
        .toSet();

    // Flutter รับได้ทั้งประกาศเป็นโฟลเดอร์ (ลงท้าย /) และระบุไฟล์ตรง ๆ
    // — โฟลเดอร์ **ไม่ลงลูก** ทุกชั้นย่อยจึงต้องประกาศเอง
    final undeclared = declared.where((p) {
      final dir = '${p.substring(0, p.lastIndexOf('/'))}/';
      return !assets.contains(p) && !assets.contains(dir);
    }).toList();

    expect(undeclared, isEmpty,
        reason: 'ยังไม่ได้ประกาศใน pubspec: ${undeclared.join(", ")}');
  });

  test('ไม่มีภาพใบไหนใหญ่เกินจำเป็นสำหรับมือถือ', () {
    // ต้นฉบับ maehmor.png เคยเป็น 6.7 MB และถูก decode เต็มความละเอียด
    // ทุกครั้งที่เปิดสแปลช — ตรึงเพดานไว้ไม่ให้ของใหญ่หลุดกลับเข้ามาอีก
    final tooBig = <String>[];
    for (final p in declared) {
      final f = File(p);
      if (f.existsSync() && f.lengthSync() > 400 * 1024) {
        tooBig.add('$p (${(f.lengthSync() / 1024).round()} KB)');
      }
    }
    expect(tooBig, isEmpty, reason: 'ภาพใหญ่เกิน 400 KB: ${tooBig.join(", ")}');
  });
}
