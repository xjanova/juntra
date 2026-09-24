import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_channel.dart';

/// ผลการตรวจอัปเดตของแอพที่ติดตั้งจาก Google Play
sealed class PlayUpdateStatus {
  const PlayUpdateStatus();
}

class PlayUpdateUpToDate extends PlayUpdateStatus {
  const PlayUpdateUpToDate();
}

class PlayUpdateAvailable extends PlayUpdateStatus {
  const PlayUpdateAvailable({required this.versionCode, required this.immediateAllowed});

  /// versionCode ของรุ่นใหม่บน Play (null ถ้า Play ไม่บอก)
  final int? versionCode;
  final bool immediateAllowed;
}

/// ตรวจไม่ได้ — ส่วนใหญ่คือแอพไม่ได้ติดตั้งจาก Play (build ของนักพัฒนา)
/// หรือเครื่องไม่มี Play Store ให้ส่งไปหน้าร้านแทน
class PlayUpdateUnavailable extends PlayUpdateStatus {
  const PlayUpdateUnavailable();
}

/// อัปเดตของช่อง Google Play — ใช้ In-App Updates API ของ Play เท่านั้น
///
/// 🔴 นโยบาย Play: แอพที่แจกผ่าน Play ห้ามอัปเดตตัวเองด้วยวิธีอื่นนอกจาก
/// กลไกของ Play ตัวอัปเดตแบบดาวน์โหลด APK (`UpdateService`) จึงห้ามทำงาน
/// ในช่องนี้เด็ดขาด — ที่นี่แค่ถาม Play ว่ามีรุ่นใหม่ไหม แล้วให้ Play เป็นคน
/// ดาวน์โหลดและติดตั้งเอง
class PlayUpdateService {
  static const _kPrefLastCheck = 'juntra_play_update_last_check_at';
  static const _kPrefDismissedCode = 'juntra_play_update_dismissed_code';

  /// ถามอัตโนมัติไม่เกินวันละ 2 ครั้ง ปุ่ม "ตรวจสอบอัปเดต" ข้ามเพดานนี้
  static const _kThrottle = Duration(hours: 12);

  Future<PlayUpdateStatus> check({bool isManual = false}) async {
    if (!Platform.isAndroid || !isPlayChannel) return const PlayUpdateUnavailable();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!isManual) {
        final last = prefs.getInt(_kPrefLastCheck) ?? 0;
        if (DateTime.now().millisecondsSinceEpoch - last < _kThrottle.inMilliseconds) {
          return const PlayUpdateUpToDate();
        }
      }
      final info = await InAppUpdate.checkForUpdate();
      await prefs.setInt(_kPrefLastCheck, DateTime.now().millisecondsSinceEpoch);

      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        return const PlayUpdateUpToDate();
      }
      final code = info.availableVersionCode;
      if (!isManual && code != null && prefs.getInt(_kPrefDismissedCode) == code) {
        return const PlayUpdateUpToDate();
      }
      return PlayUpdateAvailable(
        versionCode: code,
        immediateAllowed: info.immediateUpdateAllowed,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[PlayUpdateService] check failed: $e');
      return const PlayUpdateUnavailable();
    }
  }

  /// ให้ Play พาอัปเดตแบบเต็มจอ (Play ดาวน์โหลด+ติดตั้ง+เปิดแอพใหม่เอง)
  /// ถ้า Play ไม่ยอมให้ทำในแอพ ก็เปิดหน้าแอพบน Play Store แทน
  Future<void> startUpdate(PlayUpdateAvailable status) async {
    if (status.immediateAllowed) {
      try {
        await InAppUpdate.performImmediateUpdate();
        return;
      } catch (e) {
        if (kDebugMode) debugPrint('[PlayUpdateService] immediate failed: $e');
      }
    }
    await openStoreListing();
  }

  Future<void> dismiss(PlayUpdateAvailable status) async {
    final code = status.versionCode;
    if (code == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPrefDismissedCode, code);
  }

  /// หน้าแอพบน Play Store — `market://` เปิดแอพ Play Store ตรง ๆ
  /// ถ้าเครื่องไม่มี ค่อยตกไปเปิดในเบราว์เซอร์
  Future<void> openStoreListing() async {
    final market = Uri.parse('market://details?id=com.xjanova.juntra');
    try {
      if (await launchUrl(market, mode: LaunchMode.externalApplication)) return;
    } catch (_) {/* ไม่มี Play Store — ไปทางเว็บ */}
    await launchUrl(Uri.parse(kPlayStoreListingUrl), mode: LaunchMode.externalApplication);
  }
}

final playUpdateServiceProvider = Provider<PlayUpdateService>((ref) => PlayUpdateService());
