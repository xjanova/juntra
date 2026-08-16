import 'package:flutter_test/flutter_test.dart';
import 'package:juntra/core/update/update_info.dart';

/// หน้าต่างอัปเดตต้องไม่โผล่ชื่อหรือลิงก์ของที่เก็บไฟล์เด็ดขาด
///
/// สัญญานี้เขียนไว้ตั้งแต่วันแรกของแอพ (ผู้ใช้เห็นแค่ "เซิร์ฟเวอร์อัปเดต")
/// แต่บันทึกรุ่นที่ GitHub เขียนให้อัตโนมัติมีลิงก์ของตัวเองติดมาเสมอ และ
/// ของเดิมส่ง `body` ดิบเข้า MarkdownBody ตรง ๆ — ผู้ใช้จึงเห็น github.com
/// เต็ม ๆ สองบรรทัดกลางหน้าต่างอัปเดต
void main() {
  /// บันทึกรุ่นจริงของ v0.3.5+16 (คัดลอกมาจาก GitHub ตรง ๆ)
  const realBody = '''
## What's Changed
* feat: แอพตามเว็บทัน — Deep 39฿ + เติมเงินในแชท + หมวดคำถาม by @xjanova in https://github.com/xjanova/juntra/pull/10


**Full Changelog**: https://github.com/xjanova/juntra/compare/v0.3.4+15...v0.3.5+16
''';

  group('sanitizeReleaseNotes', () {
    test('บันทึกรุ่นจริงต้องไม่เหลือร่องรอย github เลย', () {
      final out = sanitizeReleaseNotes(realBody);

      expect(out.toLowerCase(), isNot(contains('github')));
      expect(out, isNot(contains('http')));
      expect(out, isNot(contains('@xjanova')));
      // แต่เนื้อหาที่มีประโยชน์ต้องอยู่ครบ
      expect(out, contains('แอพตามเว็บทัน'));
      expect(out, contains("What's Changed"));
    });

    test('บรรทัด Full Changelog ที่เหลือแต่หัวข้อ ต้องถูกตัดทิ้ง', () {
      final out = sanitizeReleaseNotes(realBody);
      expect(out.toLowerCase(), isNot(contains('full changelog')));
    });

    test('ลิงก์แบบ markdown เหลือแค่ป้ายข้อความ', () {
      final out = sanitizeReleaseNotes(
        'ดูรายละเอียดที่ [หน้ารุ่น](https://github.com/xjanova/juntra/releases) นะคะ',
      );
      expect(out, contains('หน้ารุ่น'));
      expect(out, isNot(contains('http')));
      expect(out.toLowerCase(), isNot(contains('github')));
    });

    test('URL โดเมนอื่นก็ต้องไม่หลุด (มิเรอร์ในอนาคต)', () {
      final out = sanitizeReleaseNotes('โหลดได้ที่ https://cdn.example.com/juntra.apk');
      expect(out, isNot(contains('http')));
      expect(out, contains('โหลดได้ที่'));
    });

    test('บันทึกรุ่นที่เขียนเองล้วน ๆ ต้องไม่ถูกแตะ', () {
      const human = '''
## สิ่งที่เปลี่ยน
* เพิ่มภาพประกอบทุกหน้า
* แก้บั๊กหักเครดิตซ้ำ
''';
      final out = sanitizeReleaseNotes(human);
      expect(out, contains('เพิ่มภาพประกอบทุกหน้า'));
      expect(out, contains('แก้บั๊กหักเครดิตซ้ำ'));
      expect(out, contains('สิ่งที่เปลี่ยน'));
    });

    test('ว่างเปล่าก็ต้องไม่พัง', () {
      expect(sanitizeReleaseNotes(''), '');
      expect(sanitizeReleaseNotes('   \n\n  '), '');
      // ถ้าเหลือแต่ลิงก์ล้วน ต้องได้สตริงว่าง (หน้าจอจะตกไปใช้ข้อความสำรอง)
      expect(sanitizeReleaseNotes('https://github.com/x/y/releases'), '');
    });
  });

  group('UpdateInfo.fromGitHubRelease', () {
    test('releaseNotesMd ที่ประกอบออกมาต้องสะอาดแล้ว', () {
      final info = UpdateInfo.fromGitHubRelease(const {
        'tag_name': 'v0.3.5+16',
        'body': realBody,
        'published_at': '2026-07-25T16:25:52Z',
        'assets': [
          {
            'name': 'juntra-0.3.5-universal.apk',
            'browser_download_url':
                'https://github.com/xjanova/juntra/releases/download/v0.3.5+16/juntra.apk',
            'size': 42,
            'digest': 'sha256:abc',
          }
        ],
      });

      expect(info.releaseNotesMd.toLowerCase(), isNot(contains('github')));
      expect(info.releaseNotesMd, isNot(contains('http')));
      // apkUrl ยังต้องใช้งานได้ตามเดิม (ภายในเท่านั้น ไม่เคยถูกวาด)
      expect(info.apkUrl, contains('juntra.apk'));
      // toString ต้องไม่พา URL ออกไปกับ log
      expect(info.toString(), isNot(contains('http')));
      expect(info.toString(), 'UpdateInfo(0.3.5+16)');
    });
  });
}
