import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/api/idempotency.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/fortune_repository.dart';
import '../../core/auth/auth_state.dart';
import '../../shared/data/juntra_art.dart';
import '../../shared/widgets/fortune_form_scaffold.dart';
import '../../shared/widgets/gold_button.dart';

/// เลขศาสตร์ — name + birth date → POST /v1/fortune/numerology → route to the
/// reading detail. Pure local math on the backend, so it always returns a
/// real result.
class NumerologyScreen extends ConsumerStatefulWidget {
  const NumerologyScreen({super.key});
  @override
  ConsumerState<NumerologyScreen> createState() => _NumerologyScreenState();
}

class _NumerologyScreenState extends ConsumerState<NumerologyScreen> {
  final _name = TextEditingController();
  DateTime? _dob;
  bool _busy = false;
  /// กันคิดเงินซ้ำเมื่อ dio retry POST เอง — คีย์เดิมตลอดการกดหนึ่งครั้ง
  final _attempt = IdempotentAttempt('numerology');
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 25),
      firstDate: DateTime(1900, 1, 2),
      lastDate: now,
    );
    if (d != null) setState(() => _dob = d);
  }

  Future<void> _submit() async {
    if (_busy) return;
    final name = _name.text.trim();
    if (name.isEmpty) return setState(() => _error = 'กรุณากรอกชื่อ-นามสกุล');
    if (_dob == null) return setState(() => _error = 'กรุณาเลือกวันเกิด');

    if (ref.read(authControllerProvider) is! AuthAuthenticated) {
      context.push(Routes.login);
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final repo = await ref.read(fortuneRepositoryProvider.future);
      final id = await repo.createNumerology(
        name: name,
        birthDate: DateFormat('yyyy-MM-dd').format(_dob!),
        idempotencyKey: _attempt.begin('$name|${DateFormat('yyyy-MM-dd').format(_dob!)}'),
      );
      _attempt.succeeded();
      // ignore: unawaited_futures
      ref.read(authControllerProvider.notifier).refresh();
      ref.invalidate(fortuneHistoryProvider);
      if (!mounted) return;
      context.pushReplacement('${Routes.reading}?id=$id');
    } on ApiException catch (e) {
      if (!mounted) return;
      // 402 เงินไม่พอ · 503 เซิร์ฟเวอร์คืนเครดิตแล้ว — ทั้งคู่ยังไม่ถูกตัดเงิน
      // เริ่มคีย์ใหม่ได้ ส่วนกรณีอื่นเก็บคีย์เดิมไว้ กดลองใหม่จะไม่โดนหักซ้ำ
      if (e.statusCode == 402 || e.statusCode == 503) _attempt.notCharged();
      if (e.statusCode == 402) {
        // ปลด busy ก่อนออกจากฟังก์ชัน — context.push เป็น push จริง หน้านี้
        // ยังอยู่ใน stack พร้อม State เดิม ผู้ใช้เติมเงินเสร็จกด back กลับมา
        // จะเจอปุ่มค้าง 'กำลังคำนวณ...' ถาวร ต้องถอยออกแล้วเข้าใหม่
        setState(() { _busy = false; _error = null; });
        context.push(Routes.wallet);
        return;
      }
      setState(() { _busy = false; _error = e.message; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _busy = false; _error = 'เกิดข้อผิดพลาด กรุณาลองใหม่'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FortuneFormScaffold(
      title: 'เลขศาสตร์',
      art: JuntraArt.numerology,
      subtitle: 'วิเคราะห์เลขชีวิต เลขนาม และเลขวันเกิดของคุณ',
      error: _error,
      busy: _busy,
      featureKey: 'numerology',
      children: [
        FortuneField(
          label: 'ชื่อ-นามสกุล',
          child: TextField(
            controller: _name,
            style: const TextStyle(color: JuntraColors.textCream, fontSize: 14),
            cursorColor: JuntraColors.gold,
            decoration: fortuneInputDecoration('เช่น สมชาย ใจดี'),
          ),
        ),
        const SizedBox(height: 14),
        FortuneField(
          label: 'วัน-เดือน-ปีเกิด',
          child: InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: JuntraColors.purple.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 18, color: JuntraColors.textFaint),
                  const SizedBox(width: 10),
                  Text(
                    _dob == null
                        ? 'แตะเพื่อเลือกวันเกิด'
                        : DateFormat('d MMMM yyyy', 'th').format(_dob!),
                    style: TextStyle(
                      fontSize: 14,
                      color: _dob == null ? JuntraColors.textFaint : JuntraColors.textCream,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        GoldButton(
          label: _busy ? 'กำลังคำนวณ...' : 'ดูเลขศาสตร์',
          icon: const Text('⊛', style: TextStyle(fontSize: 14)),
          size: GoldButtonSize.lg,
          disabled: _busy,
          onPressed: _submit,
        ),
      ],
    );
  }
}
