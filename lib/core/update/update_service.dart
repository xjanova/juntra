import 'dart:async';
import 'dart:io' show Platform, File;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/endpoints.dart';
import 'update_info.dart';

/// Possible outcomes of a version check.
sealed class UpdateStatus {
  const UpdateStatus();
}

class UpdateUpToDate extends UpdateStatus {
  const UpdateUpToDate();
}

class UpdateAvailable extends UpdateStatus {
  const UpdateAvailable({required this.info});
  final UpdateInfo info;
}

class UpdateCheckFailed extends UpdateStatus {
  const UpdateCheckFailed(this.message);
  final String message;
}

/// Download progress events.
class UpdateProgress {
  const UpdateProgress({required this.received, required this.total});
  final int received;
  final int total;
  double get fraction => total <= 0 ? 0 : received / total;
  int get percent => (fraction * 100).round();
}

/// Self-update service for the Juntra Android app.
///
/// **Important — UI separation contract:**
/// This service uses GitHub Releases as artifact storage, but ZERO upstream
/// URLs or provider names are returned to the UI layer. Callers receive
/// only [UpdateInfo] (version, changelog, opaque APK URL used for download)
/// and progress percentages. Error messages are intentionally generic
/// ("ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์อัปเดต") so dialogs never reveal the
/// upstream provider.
///
/// Flow:
///   1. [checkForUpdate] hits the public GitHub API (anonymous, 60 req/h
///      per IP — well within budget given [_kThrottleMs] = 6h).
///   2. Compares tag → `package_info_plus.version`.
///   3. Outdated → UI surfaces an UpdateDialog with Markdown changelog.
///   4. [downloadAndInstall] streams APK → app docs dir → opens via
///      OpenFilex which triggers the system install prompt.
class UpdateService {
  UpdateService();

  /// User-facing throttle: don't re-check more than every 6 hours.
  /// Manual ("ตรวจสอบอัปเดต") taps bypass throttling.
  static const int _kThrottleMs = 6 * 60 * 60 * 1000;

  static const _kPrefLastCheck = 'juntra_update_last_check_at';
  static const _kPrefDismissedVersion = 'juntra_update_dismissed_version';

  // Dedicated Dio instance — we never want pretty-logger from the API
  // client to leak GitHub URLs into release-build logs.
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(minutes: 5),
    sendTimeout: const Duration(seconds: 30),
    headers: const {
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    },
  ));

  Future<UpdateStatus> checkForUpdate({bool isManual = false}) async {
    try {
      if (!isManual && await _isThrottled()) {
        return const UpdateUpToDate();
      }

      final res = await _dio.get<Map<String, dynamic>>(
        Api.githubLatestRelease,
        options: Options(responseType: ResponseType.json),
      );
      await _stampLastCheck();

      final data = res.data;
      if (data == null) return const UpdateCheckFailed('ไม่ได้รับข้อมูลจากเซิร์ฟเวอร์อัปเดต');

      final info = UpdateInfo.fromGitHubRelease(data);
      if (info.apkUrl.isEmpty) {
        return const UpdateCheckFailed('ยังไม่พบไฟล์ติดตั้งของเวอร์ชันใหม่');
      }

      final pkg = await PackageInfo.fromPlatform();
      final cmp = compareSemver(pkg.version, info.latestVersion);
      if (cmp >= 0) return const UpdateUpToDate();

      // Honor "ข้ามเวอร์ชันนี้" until something even newer ships.
      final dismissed = await _getDismissedVersion();
      if (dismissed != null && compareSemver(dismissed, info.latestVersion) >= 0) {
        return const UpdateUpToDate();
      }

      return UpdateAvailable(info: info);
    } catch (e) {
      // Intentionally generic — never leak provider/URL in error text.
      if (kDebugMode) debugPrint('[UpdateService] check failed: $e');
      return const UpdateCheckFailed('ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์อัปเดต');
    }
  }

  /// Stream APK download progress; on completion launches the system
  /// installer. Android only.
  Stream<UpdateProgress> downloadAndInstall(UpdateInfo info) async* {
    if (!Platform.isAndroid) {
      throw UnsupportedError('การอัปเดตอัตโนมัติรองรับเฉพาะ Android');
    }

    final controller = StreamController<UpdateProgress>();
    final dir = await getApplicationDocumentsDirectory();
    // Filename intentionally generic — the user might see this in their
    // Downloads notification; "juntra-X.Y.Z.apk" reveals nothing.
    final filename = 'juntra-${info.latestVersion}.apk';
    final path = '${dir.path}/$filename';

    final file = File(path);
    if (await file.exists()) await file.delete();

    unawaited(_runDownload(info.apkUrl, path, controller));

    await for (final p in controller.stream) {
      yield p;
    }

    // Launch the OS package installer.
    final result = await OpenFilex.open(
      path,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) {
      throw StateError('เปิดไฟล์ติดตั้งไม่ได้ (${result.message})');
    }
  }

  Future<void> _runDownload(
    String url,
    String savePath,
    StreamController<UpdateProgress> controller,
  ) async {
    try {
      await _dio.download(
        url,
        savePath,
        onReceiveProgress: (r, t) {
          controller.add(UpdateProgress(received: r, total: t <= 0 ? 0 : t));
        },
      );
      controller.add(const UpdateProgress(received: 1, total: 1));
    } catch (e) {
      controller.addError('ดาวน์โหลดไม่สำเร็จ');
    } finally {
      await controller.close();
    }
  }

  Future<bool> _isThrottled() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_kPrefLastCheck) ?? 0;
    return DateTime.now().millisecondsSinceEpoch - last < _kThrottleMs;
  }

  Future<void> _stampLastCheck() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPrefLastCheck, DateTime.now().millisecondsSinceEpoch);
  }

  Future<String?> _getDismissedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kPrefDismissedVersion);
  }

  Future<void> dismissVersion(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefDismissedVersion, version);
  }
}

final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService();
});

/// Cached check result so the home badge can render without re-hitting
/// the network on every screen change.
final updateStatusProvider = FutureProvider<UpdateStatus>((ref) async {
  final svc = ref.watch(updateServiceProvider);
  return svc.checkForUpdate();
});

void unawaited(Future<void> f) {}
