import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juntra/core/api/horoscope_repository.dart';
import 'package:juntra/features/horoscope/horoscope_screen.dart';

void main() {
  testWidgets('horoscope grid retries failed signs request', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(ProviderScope(overrides: [
      horoscopeSignsProvider.overrideWith((ref) async {
        if (++attempts == 1) throw StateError('offline');
        return [{'slug': 'aries', 'name_th': 'เมษ', 'glyph': '♈'}];
      }),
    ], child: const MaterialApp(home: HoroscopeScreen())));
    await tester.pump();
    expect(find.text('โหลดดวงไม่สำเร็จ'), findsOneWidget);
    await tester.tap(find.text('ลองใหม่'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(attempts, 2);
    expect(find.text('เมษ'), findsOneWidget);
    expect(find.text('โหลดดวงไม่สำเร็จ'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
