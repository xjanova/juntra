import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/fortune_repository.dart';
import '../../core/auth/auth_state.dart';
import '../../shared/widgets/fortune_form_scaffold.dart';
import '../../shared/widgets/gold_button.dart';

/// ฤกษ์ยาม — occasion + optional date window → POST /v1/fortune/auspicious.
class AuspiciousScreen extends ConsumerStatefulWidget {
  const AuspiciousScreen({super.key});
  @override
  ConsumerState<AuspiciousScreen> createState() => _AuspiciousScreenState();
}

class _AuspiciousScreenState extends ConsumerState<AuspiciousScreen> {
  final _occasion = TextEditingController();
  DateTime? _from;
  DateTime? _to;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _occasion.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime? initial) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
  }

  Future<void> _submit() async {
    if (_busy) return;
    final occasion = _occasion.text.trim();
    if (occasion.isEmpty) return setState(() => _error = 'กรุณาระบุโอกาส/งานมงคล');

    if (ref.read(authControllerProvider) is! AuthAuthenticated) {
      context.push(Routes.login);
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final repo = await ref.read(fortuneRepositoryProvider.future);
      final fmt = DateFormat('yyyy-MM-dd');
      final id = await repo.createAuspicious(
        occasion: occasion,
        fromDate: _from == null ? null : fmt.format(_from!),
        toDate: _to == null ? null : fmt.format(_to!),
      );
      // ignore: unawaited_futures
      ref.read(authControllerProvider.notifier).refresh();
      ref.invalidate(fortuneHistoryProvider);
      if (!mounted) return;
      context.pushReplacement('${Routes.reading}?id=$id');
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 402) { context.push(Routes.wallet); return; }
      // 422 no_auspicious_day → e.message explains; user widens the window.
      setState(() { _busy = false; _error = e.message; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _busy = false; _error = 'เกิดข้อผิดพลาด กรุณาลองใหม่'; });
    }
  }

  Widget _dateField(String label, DateTime? value, ValueChanged<DateTime> onPick) {
    return Expanded(
      child: FortuneField(
        label: label,
        child: InkWell(
          onTap: () async {
            final d = await _pick(value);
            if (d != null) onPick(d);
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: JuntraColors.purple.withValues(alpha: 0.4)),
            ),
            child: Text(
              value == null ? 'ไม่ระบุ' : DateFormat('d MMM yyyy', 'th').format(value),
              style: TextStyle(
                fontSize: 13,
                color: value == null ? JuntraColors.textFaint : JuntraColors.textCream,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FortuneFormScaffold(
      title: 'ฤกษ์ยาม',
      subtitle: 'หาวันมงคลสำหรับงานสำคัญของคุณ (เว้นช่วงวันไว้ = 60 วันข้างหน้า)',
      error: _error,
      busy: _busy,
      featureKey: 'auspicious',
      children: [
        FortuneField(
          label: 'โอกาส / งานมงคล',
          child: TextField(
            controller: _occasion,
            style: const TextStyle(color: JuntraColors.textCream, fontSize: 14),
            cursorColor: JuntraColors.gold,
            decoration: fortuneInputDecoration('เช่น แต่งงาน ขึ้นบ้านใหม่ เปิดร้าน'),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _dateField('ตั้งแต่วันที่', _from, (d) => setState(() => _from = d)),
            const SizedBox(width: 10),
            _dateField('ถึงวันที่', _to, (d) => setState(() => _to = d)),
          ],
        ),
        const SizedBox(height: 24),
        GoldButton(
          label: _busy ? 'กำลังหาฤกษ์...' : 'หาฤกษ์ยาม',
          icon: const Text('☼', style: TextStyle(fontSize: 14)),
          size: GoldButtonSize.lg,
          disabled: _busy,
          onPressed: _submit,
        ),
      ],
    );
  }
}
