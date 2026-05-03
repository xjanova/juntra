import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juntra/app/app.dart';

void main() {
  testWidgets('JuntraApp boots and renders splash screen',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: JuntraApp()));
    await tester.pump(const Duration(milliseconds: 100));

    // Splash carries the brand wordmark + Mae Mor portrait.
    expect(find.text('จันทรา'), findsWidgets);
    expect(find.text('พยากรณ์'), findsWidgets);
  });
}
