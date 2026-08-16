import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/idempotency.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/fortune_repository.dart';
import '../../core/auth/auth_state.dart';
import '../../shared/data/juntra_art.dart';
import '../../shared/widgets/fortune_form_scaffold.dart';
import '../../shared/widgets/gold_button.dart';

/// ดูลายมือ — pick/take a palm photo (+ optional question) → multipart POST
/// /v1/fortune/palmistry → route to the reading detail. Needs a vision model
/// upstream; the backend refuses (503) without charging if it's unavailable.
class PalmistryScreen extends ConsumerStatefulWidget {
  const PalmistryScreen({super.key});
  @override
  ConsumerState<PalmistryScreen> createState() => _PalmistryScreenState();
}

class _PalmistryScreenState extends ConsumerState<PalmistryScreen> {
  final _picker = ImagePicker();
  final _question = TextEditingController();
  XFile? _image;
  bool _busy = false;
  /// กันคิดเงินซ้ำเมื่อ dio retry POST เอง — คีย์เดิมตลอดการกดหนึ่งครั้ง
  final _attempt = IdempotentAttempt('palmistry');
  String? _error;

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final x = await _picker.pickImage(
        source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 85,
      );
      if (x != null) setState(() { _image = x; _error = null; });
    } on Exception {
      setState(() => _error = 'เปิดกล้อง/แกลเลอรีไม่ได้ กรุณาลองใหม่');
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_image == null) return setState(() => _error = 'กรุณาถ่ายหรือเลือกรูปฝ่ามือก่อน');

    if (ref.read(authControllerProvider) is! AuthAuthenticated) {
      context.push(Routes.login);
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final repo = await ref.read(fortuneRepositoryProvider.future);
      final id = await repo.createPalmistry(
        filePath: _image!.path,
        fileName: _image!.name,
        question: _question.text,
        idempotencyKey: _attempt.begin('${_image!.path}|${_question.text.trim()}'),
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
      title: 'ดูลายมือ',
      art: JuntraArt.palmistry,
      subtitle: 'ถ่ายรูปฝ่ามือข้างที่ถนัด ให้เห็นเส้นลายมือชัด ๆ แล้วแม่หมอจะอ่านให้',
      error: _error,
      busy: _busy,
      featureKey: 'palmistry',
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Container(
            decoration: BoxDecoration(
              color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(JuntraRadius.card),
              border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.3)),
            ),
            clipBehavior: Clip.antiAlias,
            child: _image == null
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.back_hand_outlined, size: 48, color: JuntraColors.textFaint),
                        SizedBox(height: 8),
                        Text('ยังไม่มีรูปฝ่ามือ',
                            style: TextStyle(fontSize: 12, color: JuntraColors.textFaint)),
                      ],
                    ),
                  )
                : Image.file(File(_image!.path), fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: JuntraColors.gold,
                  foregroundColor: JuntraColors.bgPurpleDeep,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('ถ่ายรูป', style: TextStyle(fontWeight: FontWeight.w700)),
                onPressed: _busy ? null : () => _pick(ImageSource.camera),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: JuntraColors.purple.withValues(alpha: 0.3),
                  foregroundColor: JuntraColors.textCream,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('แกลเลอรี', style: TextStyle(fontWeight: FontWeight.w700)),
                onPressed: _busy ? null : () => _pick(ImageSource.gallery),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        FortuneField(
          label: 'คำถาม (ไม่ใส่ก็ได้)',
          child: TextField(
            controller: _question,
            maxLength: 500,
            style: const TextStyle(color: JuntraColors.textCream, fontSize: 14),
            cursorColor: JuntraColors.gold,
            decoration: fortuneInputDecoration('เช่น เส้นชีวิตเป็นอย่างไร, ดวงความรัก'),
          ),
        ),
        const SizedBox(height: 10),
        GoldButton(
          label: _busy ? 'กำลังวิเคราะห์...' : 'ดูลายมือ',
          icon: const Text('✋', style: TextStyle(fontSize: 14)),
          size: GoldButtonSize.lg,
          disabled: _busy,
          onPressed: _submit,
        ),
      ],
    );
  }
}
