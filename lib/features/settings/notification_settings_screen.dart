import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/api/app_config_repository.dart';
import '../../core/api/push_repository.dart';
import '../../core/auth/session.dart';
import '../../core/push/push_service.dart';
import '../../shared/widgets/account_feature_page.dart';

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => AccountFeaturePage<PushPreferences>(
    title: 'การแจ้งเตือน', feature: 'push', value: ref.watch(pushPreferencesProvider),
    onRetry: () => ref.invalidate(pushPreferencesProvider),
    builder: (prefs) => _PreferencesForm(key: ValueKey(ref.watch(sessionUserIdProvider)), prefs: prefs));
}

class _PreferencesForm extends ConsumerStatefulWidget {
  const _PreferencesForm({super.key, required this.prefs});
  final PushPreferences prefs;
  @override
  ConsumerState<_PreferencesForm> createState() => _PreferencesFormState();
}

class _PreferencesFormState extends ConsumerState<_PreferencesForm> {
  late Set<String> _muted = {...widget.prefs.muted};
  bool _busy = false;
  String? _message;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
    const Text('เลือกรับการแจ้งเตือนแต่ละประเภท'),
    for (final type in widget.prefs.types) SwitchListTile(
      title: Text('${type['name']}'), subtitle: Text('${type['description'] ?? ''}'),
      value: !_muted.contains('${type['key']}'),
      onChanged: _busy ? null : (enabled) => _save('${type['key']}', enabled)),
    ListTile(leading: const Icon(Icons.bedtime_outlined), title: const Text('ช่วงพักการแจ้งเตือน'),
      subtitle: Text('${widget.prefs.quietStart} – ${widget.prefs.quietEnd} น. (เวลาไทย)')),
    const SizedBox(height: 12),
    if (widget.prefs.fcm && ref.watch(appConfigValueProvider).pushFcm)
      OutlinedButton(onPressed: _busy ? null : _enable, child: const Text('เปิดการแจ้งเตือนบนเครื่องนี้'))
    else const Text('การแจ้งเตือนบนเครื่องยังไม่พร้อมใช้งาน'),
    if (_message != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_message!)),
  ]);
  Future<void> _save(String key, bool enabled) async {
    if (_busy) return;
    setState(() { _busy = true; _message = null; });
    final muted = {..._muted};
    enabled ? muted.remove(key) : muted.add(key);
    try {
      final prefs = await (await ref.read(pushRepositoryProvider.future)).save(muted);
      if (!mounted) return;
      setState(() => _muted = prefs.muted);
      ref.invalidate(pushPreferencesProvider);
    } catch (e) {
      if (mounted) setState(() => _message = e is ApiException ? e.message : 'บันทึกไม่สำเร็จ กรุณาลองใหม่');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  Future<void> _enable() async {
    if (_busy) return;
    setState(() { _busy = true; _message = null; });
    try {
      final ok = await ref.read(pushServiceProvider).register(requestPermission: true);
      if (mounted) setState(() => _message = ok ? 'เปิดการแจ้งเตือนแล้ว' : 'ยังเปิดไม่ได้ กรุณาตรวจสิทธิ์ในการตั้งค่าเครื่อง');
    } catch (e) {
      if (mounted) setState(() => _message = e is ApiException ? e.message : 'เครื่องนี้ยังไม่พร้อมรับการแจ้งเตือน');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
