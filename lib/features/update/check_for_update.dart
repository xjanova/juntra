import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/update/update_service.dart';
import 'update_dialog.dart';

/// User-initiated ("ตรวจสอบอัปเดต") update check that reports its outcome
/// inline — shared by Profile + Settings so the behaviour is identical.
///
/// - newer version → the [UpdateDialog] sheet (with changelog)
/// - already current → a "เป็นเวอร์ชันล่าสุดแล้ว" snackbar
/// - failure → a generic snackbar (never reveals the upstream provider)
///
/// `isManual: true` bypasses the 6h throttle so the tap always does a real
/// network check.
///
/// Re-entrancy guarded: a rapid double-tap is ignored while a check (or its
/// resulting dialog) is still in flight, so it can't fire two network calls
/// or stack two update sheets.
bool _checkInFlight = false;

Future<void> runManualUpdateCheck(BuildContext context, WidgetRef ref) async {
  if (_checkInFlight) return;
  _checkInFlight = true;

  final messenger = ScaffoldMessenger.of(context);
  void toast(String msg) {
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: JuntraColors.bgPurpleDeep,
      behavior: SnackBarBehavior.floating,
    ));
  }

  try {
    toast('กำลังตรวจสอบอัปเดต...');

    // checkForUpdate is contractually non-throwing (returns
    // UpdateCheckFailed), but guard anyway so a future change can't crash
    // a button tap.
    UpdateStatus status;
    try {
      status =
          await ref.read(updateServiceProvider).checkForUpdate(isManual: true);
    } catch (_) {
      status = const UpdateCheckFailed('ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์อัปเดต');
    }
    if (!context.mounted) return;

    switch (status) {
      case final UpdateAvailable s:
        messenger.hideCurrentSnackBar();
        await UpdateDialog.show(context, s);
      case UpdateUpToDate():
        toast('เป็นเวอร์ชันล่าสุดแล้ว ✨');
      case UpdateCheckFailed(:final message):
        toast(message);
    }
  } finally {
    _checkInFlight = false;
  }
}
