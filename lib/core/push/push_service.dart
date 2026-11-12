import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/endpoints.dart';
import '../app_channel.dart';

class PushService {
  PushService(this._api);
  final Future<ApiClient> Function() _api;
  FirebaseMessaging? _messaging;
  String? _token;
  String? _ownerToken;
  int _generation = 0;
  StreamSubscription<String>? _refresh;
  StreamSubscription<RemoteMessage>? _opened;
  void Function(Map<String, dynamic>)? _onOpen;
  Completer<bool>? _registration;
  Future<void> _teardown = Future.value();
  Future<bool>? _initialization;

  Future<bool> initialize() => _initialization ??= _initialize();
  Future<bool> _initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    if (_messaging != null) return true;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      _messaging = FirebaseMessaging.instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> register({
    bool requestPermission = false,
    void Function(Map<String, dynamic>)? onOpen,
  }) async {
    if (onOpen != null) _onOpen = onOpen;
    final generation = ++_generation;
    await _teardown;
    if (generation != _generation) return false;
    if (!await initialize() || generation != _generation) return false;
    final messaging = _messaging!;
    final settings = requestPermission
        ? await messaging.requestPermission()
        : await messaging.getNotificationSettings();
    if (generation != _generation) return false;
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      return false;
    }
    final api = await _api();
    final bearer = await api.getToken();
    if (bearer == null) return false;
    if (generation != _generation) return false;
    await _refresh?.cancel();
    await _opened?.cancel();
    if (_registration case final previous? when !previous.isCompleted) previous.complete(false);
    final registered = Completer<bool>();
    _registration = registered;
    _ownerToken = bearer;
    _refresh = messaging.onRegistered.listen(
      (token) async {
        if (generation != _generation) return;
        final previous = _token;
        _token = token;
        try {
          await api.post<Map<String, dynamic>>(
            Api.pushDevices,
            data: {
              'token': token,
              'platform': 'android',
              'channel': isPlayChannel ? 'play' : 'direct',
            },
            sessionToken: bearer,
          );
          if (previous != null && previous != token && generation == _generation) {
            await api.delete<Map<String, dynamic>>(
              Api.pushDevices,
              data: {'token': previous},
              sessionToken: bearer,
            );
          }
          if (!registered.isCompleted) registered.complete(generation == _generation);
        } catch (_) {
          if (!registered.isCompleted) registered.complete(false);
        }
      },
      onError: (Object error) {
        if (!registered.isCompleted) registered.complete(false);
      },
    );
    await messaging.register();
    final ok = await registered.future.timeout(const Duration(seconds: 25), onTimeout: () => false);
    if (!ok || generation != _generation) return false;
    final open = _onOpen;
    if (open != null) {
      _opened = FirebaseMessaging.onMessageOpenedApp.listen((message) {
        if (generation == _generation) open(message.data);
      });
      final initial = await messaging.getInitialMessage();
      if (initial != null && generation == _generation) open(initial.data);
    }
    return true;
  }

  Future<void> unregister() async {
    ++_generation;
    if (_registration case final pending? when !pending.isCompleted) pending.complete(false);
    final refresh = _refresh, opened = _opened;
    _refresh = null;
    _opened = null;
    final token = _token;
    final bearer = _ownerToken;
    _token = null;
    _ownerToken = null;
    final previous = _teardown;
    _teardown = () async {
      await previous;
      await refresh?.cancel();
      await opened?.cancel();
      if (token != null && bearer != null) {
        try {
          await (await _api()).delete<Map<String, dynamic>>(
            Api.pushDevices,
            data: {'token': token},
            sessionToken: bearer,
          );
        } catch (_) {}
      }
      try {
        await _messaging?.unregister();
      } catch (_) {}
    }();
    await _teardown;
  }

  void dispose() {
    ++_generation;
    if (_registration case final pending? when !pending.isCompleted) pending.complete(false);
    unawaited(_refresh?.cancel());
    unawaited(_opened?.cancel());
  }
}

final pushServiceProvider = Provider<PushService>((ref) {
  final service = PushService(() => ref.read(apiClientProvider.future));
  ref.onDispose(service.dispose);
  return service;
});
