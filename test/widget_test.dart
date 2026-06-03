import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:juntra/app/app.dart';
import 'package:juntra/shared/widgets/chantra_logo.dart';
import 'package:juntra/shared/widgets/gold_button.dart';

void main() {
  testWidgets('JuntraApp boots to the splash without overflowing',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: JuntraApp()));
    await tester.pump(const Duration(milliseconds: 100));

    // The brand wordmark is the ChantraLogo image; the gold CTA is the
    // primary action. Both are stable anchors regardless of asset loading.
    expect(find.byType(ChantraLogo), findsOneWidget);
    expect(find.byType(GoldButton), findsOneWidget);

    // The splash must not hard-overflow at the default (small) test surface —
    // it scrolls instead. takeException() would surface a RenderFlex overflow.
    expect(tester.takeException(), isNull);
  });

  testWidgets('Splash survives a very short screen', (tester) async {
    tester.view.physicalSize = const Size(360, 480); // logical ~360×480
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: JuntraApp()));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(GoldButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
