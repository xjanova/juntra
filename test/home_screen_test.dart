import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juntra/app/theme.dart';
import 'package:juntra/core/api/testimonials_repository.dart';
import 'package:juntra/features/home/home_hero.dart';
import 'package:juntra/features/home/home_screen.dart';

void main() {
  Future<void> pumpHome(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(theme: JuntraTheme.dark(), home: const HomeScreen()),
    ));
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('home draws the hero and its actions without overflowing', (tester) async {
    await pumpHome(tester, const Size(390, 844));

    expect(find.byType(HomeHero), findsOneWidget);
    expect(find.text('เปิดไพ่ยิปซีออนไลน์'), findsOneWidget);
    // คำโปรยชุดแรกเป็นของแม่หมอเหมือนเว็บ
    expect(find.text('โชคชะตา'), findsOneWidget);
    // การ์ด "ออนไลน์ · ตอบใน 8 วิ" แบบตายตัวถูกเอาออกแล้ว
    expect(find.textContaining('ตอบใน 8 วิ'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home survives a small screen, all the way down', (tester) async {
    await pumpHome(tester, const Size(320, 568));
    expect(find.byType(HomeHero), findsOneWidget);
    // ListView วาดเฉพาะส่วนที่อยู่บนจอ — เลื่อนให้ทุกส่วนได้วาดจริง
    for (var i = 0; i < 12; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    }
  });

  test('a testimonial without a name or message is dropped', () {
    expect(Testimonial.fromJson({'name': 'คุณเอ', 'message': ''}), isNull);
    expect(Testimonial.fromJson({'name': '', 'message': 'ดีมาก'}), isNull);
    final t = Testimonial.fromJson({'name': 'คุณเอ', 'message': 'แม่นมาก', 'rating': 9})!;
    expect(t.rating, 5);
    expect(t.service, isNull);
  });

  test('hero slides start with แม่หมอ and match the web count', () {
    expect(homeHeroSlides, hasLength(8));
    expect(homeHeroSlides.first.asset, contains('maemor-1'));
  });
}
