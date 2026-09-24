import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juntra/app/theme.dart';
import 'package:juntra/core/api/app_config_repository.dart';
import 'package:juntra/core/api/tarot_packages_repository.dart';
import 'package:juntra/core/app_channel.dart';
import 'package:juntra/features/reading/reading_sections_view.dart';
import 'package:juntra/shared/data/spreads.dart';
import 'package:juntra/shared/format/avatar_initial.dart';
import 'package:juntra/shared/format/credits.dart';
import 'package:juntra/shared/format/plain_preview.dart';

/// โมเดลที่แอพอ่านจากเว็บ (แพ็กเกจไพ่ · config · การ์ดคำทำนาย) และพฤติกรรมตามช่องทางแจกจ่าย
void main() {
  group('ช่องทางแจกจ่าย', () {
    test('ไม่รู้ flavor (เทสต์/บิลด์ไม่ระบุ) = ถือเป็น Google Play ไว้ก่อน', () {
      // โหมดที่เข้มกว่า: ถ้าพลาด ผลคือซ่อนตัวอัปเดต APK/พร้อมเพย์ ไม่ใช่เผลอโชว์ของต้องห้ามบน Play
      expect(appChannel, AppChannel.play);
      expect(isPlayChannel, isTrue);
    });

    test('แอพ Play แสดงค่าบริการเป็นเครดิต ไม่ใช่บาท (ราคาแพ็กบน Play รวมค่าธรรมเนียม)', () {
      expect(formatCredits(19), '19 เครดิต');
      expect(formatCredits(12.5), '12.50 เครดิต');
      expect(formatCreditsSigned(-9), '−9.00 เครดิต');
    });
  });

  group('แพ็กเกจไพ่จากเว็บ', () {
    test('อ่านแพ็กเกจครบทุกช่องที่หน้า /tarot ใช้', () {
      final p = TarotPackage.fromJson({
        'key': 'kunsai', 'type': 'tarot_kunsai', 'name_th': 'ไพ่ดูคุณไสย / โดนของ', 'cards': 10,
        'positions': List.generate(10, (i) => 'ตำแหน่ง ${i + 1}'),
        'price': 99, 'free': false, 'birth': true, 'cooldown_days': 0, 'requires_async': true,
        'image_url': 'https://xn--82c4af5bzdj.online/images/juntra/art/tarot/kunsai.webp',
        'layout': 'celtic', 'est': '10 นาที',
      });
      expect(p.type, 'tarot_kunsai');
      expect(p.cards, 10);
      expect(p.birth, isTrue);
      expect(p.requiresAsync, isTrue);
      expect(p.price, 99);
      expect(p.imageUrl, isNotNull);
    });

    test('ภาพที่ไม่ใช่ https ไม่ถูกโหลด', () {
      final p = TarotPackage.fromJson(const {
        'key': 'single', 'name_th': 'ใบเดียว', 'cards': 1, 'positions': ['คำตอบ'],
        'image_url': 'http://evil.example/x.webp',
      });
      expect(p.imageUrl, isNull);
    });

    test('สำรองตอนออฟไลน์ครั้งแรก: จำนวนใบตรงแคตตาล็อก แต่ไม่โชว์ราคาที่อาจผิด', () {
      final fallback = spreads.map(TarotPackage.fromLocal).toList();
      expect(fallback.map((p) => p.key), containsAll(spreadIds));
      for (final p in fallback) {
        expect(p.positions.length, p.cards);
        expect(p.price, isNull);
      }
    });
  });

  group('config ของแอพ', () {
    test('บริการตามสวิตช์หลังบ้าน · ไม่รู้จัก = ปิด', () {
      final cfg = AppConfig.fromJson(const {
        'services': {'tarot': true, 'chat': true, 'numerology': false, 'deep': true},
        'billing': {'google_play': true},
        'legal': {'privacy_url': 'https://xn--82c4af5bzdj.online/privacy'},
      });
      expect(cfg.isOpen('tarot'), isTrue);
      expect(cfg.isOpen('numerology'), isFalse);
      expect(cfg.isOpen('deep'), isTrue);
      expect(cfg.isOpen('palmistry'), isFalse, reason: 'ไม่อยู่ในรายการ = ปิดไว้ก่อน');
      expect(cfg.googlePlayBilling, isTrue);
    });

    test('ลิงก์นโยบายที่ไม่ใช่ https ใช้ค่ามาตรฐานแทน', () {
      final cfg = AppConfig.fromJson(const {
        'services': {},
        'legal': {'privacy_url': 'javascript:alert(1)', 'terms_url': 'http://x'},
      });
      expect(cfg.privacyUrl, AppConfig.kPrivacyUrl);
      expect(cfg.termsUrl, AppConfig.kTermsUrl);
    });

    test('ยังไม่เคยคุยกับเซิร์ฟเวอร์ได้: เหลือแค่ไพ่กับแชท', () {
      expect(AppConfig.fallback.isOpen('tarot'), isTrue);
      expect(AppConfig.fallback.isOpen('chat'), isTrue);
      expect(AppConfig.fallback.isOpen('numerology'), isFalse);
      expect(AppConfig.fallback.googlePlayBilling, isFalse);
    });
  });

  testWidgets('การ์ดคำทำนาย: ฟันธง · รายใบ · รายเดือน · ตาราง', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ReadingSectionsView(items: [
            {'type': 'verdict', 'title': 'ฟันธง', 'result': 'ใช่ค่ะ', 'fields': {}, 'items': [], 'body': 'ไพ่หนุน'},
            {'type': 'card', 'title': 'ใบที่ 2 · อีกฝ่าย', 'n': 2, 'label': 'อีกฝ่าย', 'fields': {}, 'items': [], 'body': 'เขาคิดถึง'},
            {'type': 'hearts', 'title': 'ใจเรา ใจเขา', 'fields': {'ใจเรา': 'รอ', 'ใจเขา': 'ลังเล'}, 'items': [], 'body': ''},
            {'type': 'month', 'title': 'ต.ค. 2569 · ดี', 'month': 'ต.ค. 2569', 'tone': 'good', 'tone_label': 'ดี',
              'theme': 'เริ่มใหม่', 'fields': {}, 'items': [], 'body': 'งานเข้า'},
            {'type': 'advice', 'title': 'คำแนะนำ', 'fields': {}, 'items': ['ลงมือเลย'], 'body': ''},
          ]),
        ),
      ),
    ));
    expect(find.text('ใช่ค่ะ'), findsOneWidget);
    expect(find.text('ใบที่ 2 · อีกฝ่าย'), findsOneWidget);
    expect(find.text('ใจเขา'), findsOneWidget);
    expect(find.text('รายเดือน'), findsOneWidget);
    expect(find.text('ต.ค. 2569'), findsOneWidget);
    expect(find.text('ลงมือเลย'), findsOneWidget);
  });

  testWidgets('snackbar บนพื้นม่วงเข้มอ่านออก (เดิมตัวอักษรสีเดียวกับพื้น)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: JuntraTheme.dark(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('เติมเครดิตสำเร็จแล้วค่ะ'),
              backgroundColor: JuntraColors.bgPurpleDeep,
            )),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pump();
    final style = DefaultTextStyle.of(tester.element(find.text('เติมเครดิตสำเร็จแล้วค่ะ'))).style;
    expect(style.color, isNot(JuntraColors.bgPurpleDeep));
    expect(style.color, JuntraColors.textCream);
  });

  test('อักษรบนอวตาร์: ข้ามสระหน้าของชื่อไทย', () {
    expect(avatarInitial('แขก'), 'ข');
    expect(avatarInitial('ไพลิน'), 'พ');
    expect(avatarInitial('ทดสอบ แอพ'), 'ท');
    expect(avatarInitial('  somchai'), 'S');
    expect(avatarInitial(''), '?');
  });

  group('ข้อความตัวอย่างในรายการ', () {
    test('ตัดหัวข้อ markdown / bullet ออก เหลือคำตอบ', () {
      expect(
        plainPreview('## 🎯 ฟันธง\nผล: ใช่ค่ะ\n\n## 🧭 คำแนะนำ\n- **ลงมือ**เลย\n1. บอกตรง ๆ'),
        'ผล: ใช่ค่ะ ลงมือเลย บอกตรง ๆ',
      );
    });

    test('ข้อความธรรมดาผ่านไปเหมือนเดิม · มีแต่หัวข้อก็ยังบอกเรื่องได้', () {
      expect(plainPreview('ไพ่หนุนค่ะลูก'), 'ไพ่หนุนค่ะลูก');
      expect(plainPreview('## 🎯 ฟันธง'), '🎯 ฟันธง');
      expect(plainPreview(''), '');
    });
  });
}
