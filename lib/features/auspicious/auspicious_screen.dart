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
  /// กันคิดเงินซ้ำเมื่อ dio retry POST เอง — คีย์เดิมตลอดการกดหนึ่งครั้ง
  final _attempt = IdempotentAttempt('auspicious');

  /// หมวดงานที่ผู้ใช้เลือก — null = ให้เซิร์ฟเวอร์เดาจากข้อความเหมือนเดิม
  String? _occasionType;
  String? _error;

  @override
  void dispose() {
    _occasion.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime? initial, {DateTime? first}) {
    final now = DateTime.now();
    // ปฏิทิน "ถึงวันที่" ต้องเริ่มที่ "ตั้งแต่วันที่" ไม่งั้นผู้ใช้เลือกย้อนหลังได้
    // แล้วโดน 422 (`after_or_equal:from_date`) ทั้งที่หน้าจอปล่อยให้เลือก
    final lower = first ?? now.subtract(const Duration(days: 1));
    return showDatePicker(
      context: context,
      initialDate: (initial ?? now).isBefore(lower) ? lower : (initial ?? now),
      firstDate: lower,
      // เซิร์ฟเวอร์สแกนได้สูงสุด AuspiciousScorer::MAX_SCAN_DAYS = 180 วัน
      // ถ้าปล่อยให้เลือกได้ 1 ปี ระบบจะตัดเหลือ 180 เงียบ ๆ แล้วลูกค้าเข้าใจว่า
      // ค้นครบตามที่ขอ ทั้งที่ไม่ครบ
      lastDate: now.add(const Duration(days: 179)),
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
        occasionType: _occasionType,
        fromDate: _from == null ? null : fmt.format(_from!),
        toDate: _to == null ? null : fmt.format(_to!),
        idempotencyKey: _attempt
            .begin('$occasion|${_occasionType ?? ''}|${_from ?? ''}|${_to ?? ''}'),
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
      // 422 no_auspicious_day → e.message explains; user widens the window.
      setState(() { _busy = false; _error = e.message; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _busy = false; _error = 'เกิดข้อผิดพลาด กรุณาลองใหม่'; });
    }
  }

  Widget _dateField(String label, DateTime? value, ValueChanged<DateTime> onPick, {DateTime? first}) {
    return Expanded(
      child: FortuneField(
        label: label,
        child: InkWell(
          onTap: () async {
            final d = await _pick(value, first: first);
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
      art: JuntraArt.auspicious,
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
        // หมวดงาน — น้ำหนักฤกษ์ต่างกันมากรายหมวด (แต่งงานเน้นเทวี ขึ้นบ้าน
        // เน้นภูมิปาโล รักษาโรคกลับด้านเป็นข้างแรม) ถ้าไม่ให้เลือก เซิร์ฟเวอร์
        // ต้องเดาจากคีย์เวิร์ด พิมพ์ "ฤกษ์เข้าบ้าน" ก็ตกหมวดกลางทันที
        // ได้วันคนละชุดกับที่คนเดียวกันเลือกบนเว็บ
        Consumer(builder: (context, ref, _) {
          final list = ref.watch(auspiciousOccasionsProvider).valueOrNull ?? const [];
          if (list.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: FortuneField(
              label: 'หมวดงาน',
              child: DropdownButtonFormField<String?>(
                initialValue: _occasionType,
                isExpanded: true,
                dropdownColor: JuntraColors.bgPurpleDeep,
                style: const TextStyle(color: JuntraColors.textCream, fontSize: 14),
                decoration: fortuneInputDecoration('เลือกหมวด (ไม่เลือกก็ได้)'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('ให้แม่หมอเลือกให้จากข้อความ'),
                  ),
                  for (final o in list)
                    DropdownMenuItem<String?>(
                      value: o['key']?.toString(),
                      child: Text(o['label']?.toString() ?? ''),
                    ),
                ],
                onChanged: (v) => setState(() => _occasionType = v),
              ),
            ),
          );
        }),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _dateField('ตั้งแต่วันที่', _from, (d) => setState(() {
                  _from = d;
                  // เลือก "ตั้งแต่" ใหม่แล้ว "ถึง" ที่อยู่ก่อนหน้า = ช่วงติดลบ
                  // เซิร์ฟเวอร์ตีกลับ 422 ทั้งที่หน้าจอปล่อยให้เลือกได้
                  if (_to != null && _to!.isBefore(d)) _to = null;
                })),
            const SizedBox(width: 10),
            _dateField('ถึงวันที่', _to, (d) => setState(() => _to = d),
                first: _from),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'ค้นหาได้สูงสุด 180 วันนับจากวันเริ่ม',
          style: TextStyle(fontSize: 11, color: JuntraColors.textFaint),
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
