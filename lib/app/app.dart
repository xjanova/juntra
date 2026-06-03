import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      // UpdateObserver kicks off the (silent) version check as soon as
      // the first frame renders. It overlays an update sheet once the
      // splash gate finishes if a newer release is available.
      builder: (context, child) {
        return UpdateObserver(child: child ?? const SizedBox.shrink());
      },
    );
  }
}
