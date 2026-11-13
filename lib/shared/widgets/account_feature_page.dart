import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/app_config_repository.dart';
import '../../core/auth/auth_state.dart';
import 'starry_background.dart';

class AccountFeaturePage<T> extends ConsumerWidget {
  const AccountFeaturePage({
    super.key,
    required this.title,
    required this.feature,
    required this.value,
    required this.onRetry,
    required this.builder,
  });
  final String title, feature;
  final AsyncValue<T?> value;
  final VoidCallback onRetry;
  final Widget Function(T) builder;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final cfg = ref.watch(appConfigProvider);
    Widget message(String text, [Widget? action]) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            ?action,
          ],
        ),
      ),
    );
    final Widget body;
    if (auth is AuthUnknown || cfg.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (auth is AuthGuest) {
      body = message(
        'เข้าสู่ระบบเพื่อใช้$title',
        TextButton(onPressed: () => context.push(Routes.login), child: const Text('เข้าสู่ระบบ')),
      );
    } else if (auth is AuthOffline) {
      body = message(
        'เชื่อมต่อไม่ได้ กรุณาลองใหม่',
        TextButton(
          onPressed: () => ref.read(authControllerProvider.notifier).retryBootstrap(),
          child: const Text('ลองใหม่'),
        ),
      );
    } else if (!(cfg.valueOrNull?.has(feature) ?? false)) {
      body = message('ยังไม่เปิดให้บริการ');
    } else {
      body = value.when(
        data: (data) => data == null ? message('ยังไม่เปิดให้บริการ') : builder(data),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => message(
          e is ApiException ? e.message : 'โหลดข้อมูลไม่ได้',
          TextButton(onPressed: onRetry, child: const Text('ลองใหม่')),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Stack(
        children: [
          const StarryBackground(density: 24),
          Positioned.fill(child: body),
        ],
      ),
    );
  }
}
