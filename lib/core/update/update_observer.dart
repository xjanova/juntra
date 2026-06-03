import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../features/update/update_dialog.dart';
import 'update_service.dart';

/// Triggers a single update check after the first frame, then optionally
/// shows the UpdateDialog over the active route.
///
/// Sits in `MaterialApp.router`'s `builder:` callback (above the Navigator)
/// — we route the dialog through [rootNavigatorKey] so the Navigator is
/// always reachable.
class UpdateObserver extends ConsumerStatefulWidget {
  const UpdateObserver({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<UpdateObserver> createState() => _UpdateObserverState();
}

class _UpdateObserverState extends ConsumerState<UpdateObserver> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    // Sideload update path is Android-only; iOS would go via TestFlight.
    if (!Platform.isAndroid) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_checked) {
        _checked = true;
        _runCheck();
      }
    });
  }

  Future<void> _runCheck() async {
    try {
      final svc = ref.read(updateServiceProvider);
      final status = await svc.checkForUpdate();
      if (!mounted) return;

      if (kDebugMode) debugPrint('[UpdateObserver] $status');

      if (status is! UpdateAvailable) return;

      // Wait one extra frame so the splash screen has time to render
      // before the update sheet pushes over it.
      await Future<void>.delayed(const Duration(milliseconds: 1800));
      if (!mounted) return;

      final navCtx = rootNavigatorKey.currentContext;
      if (navCtx == null || !navCtx.mounted) return;
      await UpdateDialog.show(navCtx, status);
    } catch (e) {
      if (kDebugMode) debugPrint('[UpdateObserver] $e');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
