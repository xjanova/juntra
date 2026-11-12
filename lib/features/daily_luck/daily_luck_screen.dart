import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/account_repository.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/auth/auth_state.dart';
import '../../core/auth/session.dart';
import '../../shared/widgets/account_feature_page.dart';
import '../../shared/widgets/gold_button.dart';

class DailyLuckScreen extends ConsumerWidget {
  const DailyLuckScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => AccountFeaturePage<DailyLuck>(
    title: 'ดวงเสี่ยงทายประจำวัน', feature: 'daily_luck',
    value: ref.watch(dailyLuckProvider), onRetry: () => ref.invalidate(dailyLuckProvider),
    builder: (luck) => ListView(padding: const EdgeInsets.all(20), children: [
      DailyLuckCard(key: ValueKey(ref.watch(sessionUserIdProvider)), luck: luck),
      for (final earned in luck.earned) ListTile(leading: const Icon(Icons.workspace_premium),
        title: Text('${earned['label'] ?? ''}'), subtitle: Text('${earned['days']} วัน')),
    ]),
  );
}

class DailyLuckCard extends ConsumerStatefulWidget {
  const DailyLuckCard({super.key, required this.luck});
  final DailyLuck luck;
  @override
  ConsumerState<DailyLuckCard> createState() => _DailyLuckCardState();
}

class _DailyLuckCardState extends ConsumerState<DailyLuckCard> {
  bool _busy = false;
  String? _error;
  DailyLuck? _updated;
  @override
  void didUpdateWidget(covariant DailyLuckCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.luck != widget.luck) _updated = null;
  }
  @override
  Widget build(BuildContext context) {
    final luck = _updated ?? widget.luck;
    return Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('เช็กอินต่อเนื่อง ${luck.streak} วัน', style: baiJamjuree(size: 20)),
        if (luck.nextMilestone case final next?) Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text('อีก ${next['left']} วัน · ${next['label']}')),
        if (luck.reading case final reading?) ...[
          const Divider(), ..._reading(reading),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!)),
        const SizedBox(height: 12),
        GoldButton(label: _busy ? 'กำลังเช็กอิน...' : luck.checkedIn ? 'เช็กอินวันนี้แล้ว' : 'เช็กอินรับดวงวันนี้',
          onPressed: luck.checkedIn || _busy ? null : _checkin),
      ])));
  }
  List<Widget> _reading(Map<String, dynamic> reading) => [
    if (reading['day_name'] != null) Text('วัน${reading['day_name']}'),
    if (reading['day_color'] is Map) Text('สีประจำวัน · ${reading['day_color']['name']}'),
    if (reading['lucky_color'] is Map) Text('สีเสริมดวง · ${reading['lucky_color']['name']}'),
    if (reading['number'] != null) Text('เลขเสี่ยงทาย · ${reading['number']}'),
    if (reading['direction'] != null) Text('ทิศมงคล · ${reading['direction']}'),
    for (final key in ['blessing'])
      if (reading[key] is String && (reading[key] as String).isNotEmpty)
        Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(reading[key] as String)),
  ];
  Future<void> _checkin() async {
    if (_busy) return;
    final user = ref.read(sessionUserIdProvider);
    setState(() { _busy = true; _error = null; });
    try {
      final repo = await ref.read(accountRepositoryProvider.future);
      final luck = await repo.checkin();
      if (!mounted || user != ref.read(sessionUserIdProvider)) return;
      setState(() => _updated = luck);
      ref.invalidate(dailyLuckProvider);
      await ref.read(authControllerProvider.notifier).refresh();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'เช็กอินไม่สำเร็จ กรุณาลองใหม่');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
