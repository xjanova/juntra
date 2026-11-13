import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../api/account_repository.dart';
import '../api/app_config_repository.dart';
import '../auth/session.dart';
import '../app_channel.dart';
import 'push_service.dart';

String? pushRoute(Map<String, dynamic> data) {
  final reading = int.tryParse('${data['reading_id']}');
  if (reading != null && reading > 0) return '${Routes.reading}?id=$reading';
  final conversation = int.tryParse('${data['conversation_id']}');
  if (conversation != null && conversation > 0) return '${Routes.chat}?id=$conversation';
  final url = Uri.tryParse('${data['url'] ?? ''}');
  if (url != null &&
      (url.host.isEmpty ||
          (url.scheme == 'https' &&
              const ['xn--82c4af5bzdj.online', 'จันทรา.online'].contains(url.host)))) {
    final match = RegExp(r'^/reading/([1-9][0-9]*)$').firstMatch(url.path);
    if (match != null) return '${Routes.reading}?id=${match[1]}';
    if (url.path == '/account/dashboard' && url.fragment == 'daily-luck') return Routes.dailyLuck;
    if (!isPlayChannel && RegExp(r'^/wallet/topup/[1-9][0-9]*$').hasMatch(url.path)) {
      return Routes.wallet;
    }
    if (url.path == '/account/dashboard') return Routes.profile;
  }
  if (data['type'] == 'daily') return Routes.dailyLuck;
  if (data['type'] == 'reading_ready') return Routes.history;
  return null;
}

class PushBootstrap extends ConsumerStatefulWidget {
  const PushBootstrap({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<PushBootstrap> createState() => _PushBootstrapState();
}

class _PushBootstrapState extends ConsumerState<PushBootstrap> with WidgetsBindingObserver {
  String? _activeUser;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(dailyLuckProvider);
      ref.invalidate(accountProfileProvider);
      unawaited(_sync());
    }
  }

  Future<void> _sync() async {
    final user = ref.read(sessionUserIdProvider);
    final cfg = ref.read(appConfigValueProvider);
    if (user == null || !cfg.has('push') || !cfg.pushFcm) return;
    _activeUser = user;
    try {
      await ref
          .read(pushServiceProvider)
          .register(
            onOpen: (data) {
              if (!mounted || _activeUser != user || ref.read(sessionUserIdProvider) != user) {
                return;
              }
              final route = pushRoute(data);
              if (route != null) ref.read(routerProvider).push(route);
            },
          );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sessionUserIdProvider, (previous, user) {
      // Logout or a direct switch A → B: drop A's device token before B registers.
      if (previous != null && previous != user) {
        _activeUser = null;
        unawaited(ref.read(pushServiceProvider).unregister());
      }
      unawaited(_sync());
    });
    ref.listen(appConfigProvider, (_, _) => unawaited(_sync()));
    return widget.child;
  }
}
