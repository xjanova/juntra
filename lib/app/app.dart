import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/billing/play_billing_bootstrap.dart';
import '../core/update/update_observer.dart';
import 'router.dart';
import 'theme.dart';

class JuntraApp extends ConsumerWidget {
  const JuntraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'จันทราพยากรณ์',
      debugShowCheckedModeBanner: false,
      theme: JuntraTheme.dark(),
      routerConfig: router,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      // แอพภาษาไทยล้วน — ปฏิทิน/ตัวเลือกวันที่ของ Material ต้องเป็นภาษาไทยด้วย
      // (เดิมไม่ได้ตั้ง delegates ตัวเลือกวันเกิดจึงขึ้นเป็นภาษาอังกฤษ)
      locale: const Locale('th', 'TH'),
      supportedLocales: const [Locale('th', 'TH'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // UpdateObserver kicks off the (silent) version check as soon as
      // the first frame renders. It overlays an update sheet once the
      // splash gate finishes if a newer release is available.
      // PlayBillingBootstrap delivers Google Play purchases that completed
      // while the app was closed (Play channel only).
      builder: (context, child) {
        return PlayBillingBootstrap(
          child: UpdateObserver(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}
