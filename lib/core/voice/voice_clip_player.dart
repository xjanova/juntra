import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../api/api_client.dart';
import 'media_url.dart';

/// เล่นเสียงของห้อง (เสียงทักห้อง · เสียงคำตอบพรีเมียม) ทีละคลิป
///
/// - โหลดไฟล์ลงที่ชั่วคราวก่อนแล้วเล่นจากไฟล์ (เสียงคำตอบต้องแนบ bearer — ตัวเล่นเสียง
///   ส่ง header เองไม่ได้) · bearer แนบเฉพาะ URL บนโฮสต์ของ API เท่านั้น
/// - เล่นคลิปใหม่ = หยุดคลิปเดิมก่อนเสมอ (ไม่มีเสียงซ้อนกัน)
/// - เจ้าของหน้าจอต้องเรียก [dispose] — ปล่อยตัวเล่นเสียงและลบไฟล์ชั่วคราวทั้งหมด
class VoiceClipPlayer {
  VoiceClipPlayer(this._api);

  final Future<ApiClient> Function() _api;

  AudioPlayer? _player;
  StreamSubscription<void>? _completeSub;
  final _files = <String, File>{};
  CancelToken? _active;
  Dio? _plain;
  int _generation = 0;
  bool _disposed = false;

  /// URL ที่กำลังโหลด/เล่นอยู่ (null = เงียบ) — ฟองข้อความใช้สลับปุ่ม "ฟังเสียง" / "หยุด"
  final ValueNotifier<String?> current = ValueNotifier<String?>(null);

  /// ไฟล์เสียงสั้น ๆ — ใหญ่เกินนี้ไม่โหลด (กันเน็ตลูกค้าหมดเพราะไฟล์ผิดปกติ)
  static const _maxBytes = 8 * 1024 * 1024;

  /// เล่น [url] — คืน false เมื่อโหลด/เล่นไม่ได้ (หน้าจอบอกลูกค้าเองว่า "เล่นเสียงไม่ได้")
  /// [auth] = ต้องแนบ bearer (เสียงคำตอบพรีเมียม)
  Future<bool> play(String url, {bool auth = false}) async {
    if (_disposed) return false;
    final gen = ++_generation;
    _active?.cancel('superseded');
    await _stopPlayer();
    current.value = url;
    try {
      final file = _files[url] ?? await _download(url, auth: auth);
      if (_disposed || gen != _generation) return false;
      if (file == null) {
        _clear(gen);
        return false;
      }
      _files[url] = file;
      final player = _player ??= _newPlayer();
      await player.play(DeviceFileSource(file.path));
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[VoiceClip] play failed: $e');
      _clear(gen);
      return false;
    }
  }

  /// หยุดเสียงที่เล่นอยู่ (และเลิกเล่นคลิปที่กำลังโหลด)
  Future<void> stop() async {
    if (_disposed) return;
    _generation++;
    _active?.cancel('stopped');
    current.value = null;
    await _stopPlayer();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _active?.cancel('disposed');
    await _completeSub?.cancel();
    final p = _player;
    _player = null;
    try {
      await p?.stop();
      await p?.dispose();
    } catch (_) {/* ตัวเล่นปิดไปแล้ว */}
    current.dispose();
    for (final f in _files.values) {
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {/* ระบบลบ temp ให้เองภายหลัง */}
    }
    _files.clear();
    _plain?.close(force: true);
  }

  AudioPlayer _newPlayer() {
    final p = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
    _completeSub = p.onPlayerComplete.listen((_) {
      if (!_disposed) current.value = null;
    });
    return p;
  }

  void _clear(int gen) {
    if (!_disposed && gen == _generation) current.value = null;
  }

  Future<void> _stopPlayer() async {
    try {
      await _player?.stop();
    } catch (_) {/* ไม่มีอะไรเล่นอยู่ */}
  }

  Future<File?> _download(String url, {required bool auth}) async {
    final target = mediaUrl(url);
    final dir = Directory('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}juntra_voice');
    if (!await dir.exists()) await dir.create(recursive: true);
    final name = '${DateTime.now().microsecondsSinceEpoch}-${url.hashCode.toUnsigned(32).toRadixString(16)}.mp3';
    final file = File('${dir.path}${Platform.pathSeparator}$name');

    final api = await _api();
    // bearer แนบเฉพาะโฮสต์ของเรา — URL อื่น (CDN) ใช้ Dio เปล่าที่ไม่มี token
    final useAuth = auth && sameHost(target, api.dio.options.baseUrl);
    final dio = useAuth ? api.dio : (_plain ??= Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        )));
    final cancel = _active = CancelToken();
    try {
      final res = await dio.download(
        target,
        file.path,
        cancelToken: cancel,
        options: Options(headers: {'Accept': 'audio/mpeg, audio/*'}),
        onReceiveProgress: (got, _) {
          if (got > _maxBytes) cancel.cancel('too large');
        },
      );
      // ApiClient รับ 4xx โดยไม่โยน error — ไฟล์ที่ได้คือ JSON ข้อผิดพลาด ไม่ใช่เสียง
      final ok = (res.statusCode ?? 0) >= 200 && (res.statusCode ?? 0) < 300;
      if (!ok) {
        if (await file.exists()) await file.delete();
        return null;
      }
      return file;
    } catch (e) {
      if (kDebugMode) debugPrint('[VoiceClip] download failed: $e');
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
      return null;
    }
  }
}
