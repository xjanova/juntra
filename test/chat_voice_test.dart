import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juntra/core/voice/voice_clip_player.dart';

class _AudioAdapter implements HttpClientAdapter {
  RequestOptions? request;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) async {
    request = options;
    return ResponseBody.fromString('not audio', 404);
  }
  @override
  void close({bool force = false}) {}
}

void main() {
  test('public reply audio never has bearer; failures remove temporary files', () async {
    final root = await Directory.systemTemp.createTemp('juntra_audio_test_');
    final adapter = _AudioAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final player = VoiceClipPlayer(client: dio, temporaryDirectory: () async => root);
    try {
      expect(await player.play('https://cdn.example/reply.mp3'), isFalse);
      expect(adapter.request!.headers.keys.map((key) => key.toLowerCase()), isNot(contains('authorization')));
      expect(player.current.value, isNull);
      await player.dispose();
      expect(await root.list().toList(), isEmpty);
    } finally {
      await player.dispose();
      await root.delete(recursive: true);
    }
  });

  test('dispose during directory lookup prevents late download and cleans folder', () async {
    final root = await Directory.systemTemp.createTemp('juntra_audio_test_');
    final directory = Completer<Directory>();
    final lookup = Completer<void>();
    final adapter = _AudioAdapter();
    final player = VoiceClipPlayer(client: Dio()..httpClientAdapter = adapter,
      temporaryDirectory: () {
        lookup.complete();
        return directory.future;
      });
    final playing = player.play('https://cdn.example/reply.mp3');
    await lookup.future;
    final disposing = player.dispose();
    directory.complete(root);
    expect(await playing, isFalse);
    await disposing;
    expect(adapter.request, isNull);
    expect(await root.list().toList(), isEmpty);
    await root.delete(recursive: true);
  });

  test('rapid play then stop cannot restart late playback or notify after disposal', () async {
    final player = VoiceClipPlayer();
    final playing = player.play('https://cdn.example/reply.mp3');
    await player.stop();
    expect(await playing, isFalse);
    expect(player.current.value, isNull);
    await player.dispose();
    expect(await player.play('https://cdn.example/reply.mp3'), isFalse);
  });
}
