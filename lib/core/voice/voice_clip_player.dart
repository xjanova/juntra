import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'media_url.dart';

/// เสียงห้องและ reply_voice เป็น public URL ของ R2/Thaiprompt ตาม API contract
/// ใช้ client แยกที่ไม่มี bearer เสมอ และลบไฟล์ของหน้าจอนี้ทั้งหมดเมื่อปิด
class VoiceClipPlayer {
  VoiceClipPlayer({
    Dio? client,
    Future<Directory> Function()? temporaryDirectory,
  }) : _client =
           client ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 30),
             ),
           ),
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final Dio _client;
  final Future<Directory> Function() _temporaryDirectory;
  AudioPlayer? _player;
  StreamSubscription<void>? _completeSub;
  final _files = <String, File>{};
  final _downloads = <Future<File?>>{};
  Future<Directory>? _directory;
  Future<void> _operations = Future.value();
  CancelToken? _active;
  int _generation = 0;
  bool _disposed = false;

  final ValueNotifier<String?> current = ValueNotifier<String?>(null);
  static const _maxBytes = 8 * 1024 * 1024;

  Future<void> _serialize(Future<void> Function() action) {
    return _operations = _operations.then((_) => action()).catchError((
      Object e,
    ) {
      if (kDebugMode) debugPrint('[VoiceClip] player failed: $e');
    });
  }

  Future<bool> play(String url) async {
    if (_disposed || Uri.tryParse(url)?.scheme != 'https') return false;
    final gen = ++_generation;
    _active?.cancel('superseded');
    final cancel = _active = CancelToken();
    current.value = url;
    await _serialize(() async => _player?.stop());
    if (_disposed || gen != _generation) return false;
    try {
      File? file = _files[url];
      if (file == null) {
        final download = _download(url, cancel);
        _downloads.add(download);
        try {
          file = await download;
        } finally {
          _downloads.remove(download);
        }
      }
      if (_disposed || gen != _generation) return false;
      if (file == null) {
        _clear(gen);
        return false;
      }
      _files[url] = file;
      var played = false;
      await _serialize(() async {
        if (_disposed || gen != _generation) return;
        final player = _player ??= _newPlayer();
        await player.play(DeviceFileSource(file!.path));
        played = true;
      });
      if (!played) _clear(gen);
      return played && !_disposed && gen == _generation;
    } catch (e) {
      if (kDebugMode) debugPrint('[VoiceClip] play failed: $e');
      _clear(gen);
      return false;
    }
  }

  Future<void> stop() async {
    if (_disposed) return;
    _generation++;
    _active?.cancel('stopped');
    current.value = null;
    await _serialize(() async => _player?.stop());
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _active?.cancel('disposed');
    await Future.wait(_downloads.toList());
    await _completeSub?.cancel();
    await _serialize(() async {
      await _player?.stop();
      await _player?.dispose();
      _player = null;
    });
    current.dispose();
    _files.clear();
    try {
      final directory = await _directory;
      if (directory != null && await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } catch (_) {
      /* ระบบอาจลบ temp ไปแล้ว */
    }
    _client.close(force: true);
  }

  AudioPlayer _newPlayer() {
    final player = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
    _completeSub = player.onPlayerComplete.listen((_) {
      if (!_disposed) current.value = null;
    });
    return player;
  }

  void _clear(int gen) {
    if (!_disposed && gen == _generation) current.value = null;
  }

  Future<File?> _download(String url, CancelToken cancel) async {
    File? file;
    try {
      final dir = await (_directory ??= _temporaryDirectory().then(
        (root) => root.createTemp('juntra_voice_'),
      ));
      if (_disposed || cancel.isCancelled) return null;
      file = File(
        '${dir.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}.mp3',
      );
      final res = await _client.download(
        mediaUrl(url),
        file.path,
        cancelToken: cancel,
        options: Options(
          headers: {'Accept': 'audio/mpeg, audio/*'},
          followRedirects: false,
        ),
        onReceiveProgress: (got, _) {
          if (got > _maxBytes) cancel.cancel('too large');
        },
      );
      final status = res.statusCode ?? 0;
      if (_disposed || cancel.isCancelled || status < 200 || status >= 300) {
        if (await file.exists()) await file.delete();
        return null;
      }
      return file;
    } catch (e) {
      if (kDebugMode) debugPrint('[VoiceClip] download failed: $e');
      try {
        if (file != null && await file.exists()) await file.delete();
      } catch (_) {}
      return null;
    }
  }
}
