import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/deep_repository.dart';
import '../../core/auth/auth_state.dart';
import '../../shared/widgets/starry_background.dart';

/// ดูดวงเชิงลึก 39฿ — แพ็กเดียวกับที่ขายบนเว็บ จันทรา.online และบอท FB/LINE
///
/// ก่อนหน้านี้แพ็กนี้มีเฉพาะในแชท FB/LINE แล้วเพิ่งขึ้นเว็บ แอพเลยเป็นช่องทาง
/// เดียวที่ยังขายไม่ได้ ทั้งที่เป็นแพ็กที่ลูกค้าซื้อบ่อยที่สุด
///
/// เรื่องเงิน: เซิร์ฟเวอร์หักเครดิตก่อนเรียก AI และคืนเครดิตเองทุกครั้งที่
/// ไม่ได้คำทำนายจริง — หน้าจอนี้จึงแค่รายงานตามที่เซิร์ฟเวอร์บอก ห้ามเดาเอง
class DeepScreen extends ConsumerStatefulWidget {
  const DeepScreen({super.key});

  @override
  ConsumerState<DeepScreen> createState() => _DeepScreenState();
}

class _DeepScreenState extends ConsumerState<DeepScreen> {
  static const _maxQuestions = 3;

  final _controllers = List.generate(_maxQuestions, (_) => TextEditingController());
  DateTime? _birthDate;
  bool _sending = false;
  String? _error;

  /// เก็บคีย์ไว้ใช้ซ้ำเมื่อกดลองใหม่ข้อเดิม — dio retry POST อัตโนมัติ
  /// ถ้าสุ่มใหม่ทุกครั้ง ลูกค้าอาจถูกตัดเงินสองรอบจากการกดครั้งเดียว
  String? _pendingKey;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  String _newKey() {
    final r = math.Random();
    return 'deep-${DateTime.now().microsecondsSinceEpoch}-'
        '${List.generate(4, (_) => r.nextInt(36).toRadixString(36)).join()}';
  }

  List<String> get _questions => _controllers
      .map((c) => c.text.trim())
      .where((t) => t.isNotEmpty)
      .toList();

  Future<void> _submit() async {
    if (_sending) return;

    final questions = _questions;
    if (questions.isEmpty) {
      setState(() => _error = 'กรุณาพิมพ์คำถามอย่างน้อย 1 ข้อค่ะ');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    _pendingKey ??= _newKey();

    try {
      final repo = await ref.read(deepRepositoryProvider.future);
      final res = await repo.create(
        questions: questions,
        birthDate: _birthDate == null
            ? null
            : '${_birthDate!.year.toString().padLeft(4, '0')}-'
                '${_birthDate!.month.toString().padLeft(2, '0')}-'
                '${_birthDate!.day.toString().padLeft(2, '0')}',
        idempotencyKey: _pendingKey!,
      );
      if (!mounted) return;

      _pendingKey = null;                       // สำเร็จแล้ว รอบหน้าใช้คีย์ใหม่
      ref.invalidate(deepInfoProvider);         // ยอดคงเหลือเปลี่ยน
      ref.read(authControllerProvider.notifier).refresh();

      await _showResult(res);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 402) {
        _pendingKey = null;                     // ยังไม่ถูกตัดเงิน เริ่มใหม่ได้
        setState(() => _error = e.message);
        await _offerTopUp(e.message);
      } else {
        // 503 = เซิร์ฟเวอร์คืนเครดิตให้แล้ว · 409 = รายการเดิมกำลังประมวลผล
        if (e.statusCode == 503) _pendingKey = null;
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'เครือข่ายมีปัญหาค่ะ กดลองใหม่อีกครั้งได้เลย');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _offerTopUp(String message) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: JuntraColors.bgPurpleDeep,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('เครดิตไม่พอ', style: baiJamjuree(size: 18, color: JuntraColors.gold)),
              const SizedBox(height: 8),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13, color: JuntraColors.textLavender, height: 1.5,
                  )),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: JuntraColors.gold,
                    foregroundColor: JuntraColors.bgPurpleDeep,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    context.push(Routes.wallet);
                  },
                  child: const Text('ไปเติมเครดิต',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showResult(Map<String, dynamic> res) async {
    final text = res['reading']?.toString() ?? '';
    if (text.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: JuntraColors.bgPurpleDeep,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, scroll) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: JuntraColors.gold.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Text('คำทำนายเชิงลึก', style: baiJamjuree(size: 19, color: JuntraColors.gold)),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  controller: scroll,
                  child: MarkdownBody(
                    data: text,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(
                        fontSize: 14, color: JuntraColors.textLavender, height: 1.7,
                      ),
                      strong: const TextStyle(
                        fontWeight: FontWeight.w700, color: JuntraColors.textCream,
                      ),
                      h1: baiJamjuree(size: 17, color: JuntraColors.gold),
                      h2: baiJamjuree(size: 15.5, color: JuntraColors.gold),
                      h3: baiJamjuree(size: 14.5, color: JuntraColors.gold),
                      listBullet: const TextStyle(
                        fontSize: 14, color: JuntraColors.textLavender,
                      ),
                      blockSpacing: 8,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: JuntraColors.gold,
                    foregroundColor: JuntraColors.bgPurpleDeep,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('เรียบร้อย', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (mounted) {
      for (final c in _controllers) {
        c.clear();
      }
      setState(() {});
    }
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 30, now.month, now.day),
      firstDate: DateTime(1920),
      lastDate: now.subtract(const Duration(days: 1)),
      helpText: 'เลือกวันเกิดของคุณ',
    );
    if (picked != null && mounted) {
      setState(() => _birthDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(deepInfoProvider);

    return Scaffold(
      body: Stack(
        children: [
          const StarryBackground(density: 26, intensity: 0.4),
          SafeArea(
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, color: JuntraColors.gold, size: 28),
                      onPressed: () =>
                          context.canPop() ? context.pop() : context.go(Routes.home),
                    ),
                    Expanded(
                      child: Text('ดูดวงเชิงลึก',
                          style: baiJamjuree(size: 17, color: JuntraColors.gold)),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                    children: [
                      const Text(
                        'แม่หมออ่านดวงชะตาจากวันเกิดของคุณ แล้วตอบคำถามที่ค้างคาใจ '
                        'ทีละข้อ — แพ็กเดียวกับที่แม่หมอทำนายให้ลูกค้าในแชท Facebook / LINE',
                        style: TextStyle(
                          fontSize: 13.5, color: JuntraColors.textMuted, height: 1.7,
                        ),
                      ),
                      const SizedBox(height: 18),

                      info.when(
                        loading: () => const LinearProgressIndicator(
                          minHeight: 2,
                          backgroundColor: Colors.transparent,
                          valueColor: AlwaysStoppedAnimation<Color>(JuntraColors.gold),
                        ),
                        error: (_, _) => const SizedBox.shrink(),
                        data: (d) => _PriceBar(
                          cost: (d['cost'] as num?)?.toDouble() ?? 0,
                          balance: (d['balance'] as num?)?.toDouble() ?? 0,
                        ),
                      ),

                      const SizedBox(height: 18),
                      _label('วันเกิดของคุณ  (ไม่บังคับ แต่ใส่แล้วแม่นกว่ามาก)'),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: _pickBirthDate,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          decoration: BoxDecoration(
                            color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: JuntraColors.gold.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.cake_outlined,
                                  size: 18, color: JuntraColors.gold),
                              const SizedBox(width: 10),
                              Text(
                                _birthDate == null
                                    ? 'แตะเพื่อเลือกวันเกิด'
                                    : '${_birthDate!.day}/${_birthDate!.month}/${_birthDate!.year}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _birthDate == null
                                      ? JuntraColors.textFaint
                                      : JuntraColors.textCream,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),
                      _label('เรื่องที่อยากให้แม่หมอดู  (ถามได้ถึง $_maxQuestions ข้อ)'),
                      const SizedBox(height: 8),
                      for (var i = 0; i < _maxQuestions; i++) ...[
                        TextField(
                          controller: _controllers[i],
                          enabled: !_sending,
                          maxLength: 500,
                          maxLines: 2,
                          minLines: 1,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(
                            color: JuntraColors.textCream, fontSize: 14,
                          ),
                          cursorColor: JuntraColors.gold,
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: i == 0
                                ? 'เช่น ปีนี้การงานจะเป็นอย่างไร ควรย้ายงานไหม'
                                : 'ข้อที่ ${i + 1} (ไม่บังคับ)',
                            hintStyle: const TextStyle(
                              color: JuntraColors.textFaint, fontSize: 13,
                            ),
                            filled: true,
                            fillColor: JuntraColors.bgPurpleDeep.withValues(alpha: 0.6),
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      if (_error != null) ...[
                        const SizedBox(height: 4),
                        Text(_error!,
                            style: const TextStyle(fontSize: 12.5, color: Color(0xFFF59999))),
                        const SizedBox(height: 10),
                      ],

                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: JuntraColors.gold,
                            foregroundColor: JuntraColors.bgPurpleDeep,
                            disabledBackgroundColor: JuntraColors.bgPurple,
                            disabledForegroundColor: JuntraColors.textFaint,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: (_sending || _questions.isEmpty) ? null : _submit,
                          child: Text(
                            _sending ? 'แม่หมอกำลังเพ่งดวงชะตา ⋯' : 'ให้แม่หมอทำนาย',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'คำทำนายอาจใช้เวลาสักครู่ กรุณาอย่าปิดหน้านี้นะคะ\n'
                        'ถ้าระบบขัดข้อง เครดิตจะถูกคืนให้อัตโนมัติ',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5, color: JuntraColors.textFaint, height: 1.7,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 12, color: JuntraColors.textMuted, letterSpacing: 0.3,
        ),
      );
}

class _PriceBar extends StatelessWidget {
  const _PriceBar({required this.cost, required this.balance});

  final double cost;
  final double balance;

  @override
  Widget build(BuildContext context) {
    final low = balance < cost;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: JuntraColors.gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: JuntraColors.gold.withValues(alpha: low ? 0.55 : 0.22),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 16, color: JuntraColors.gold),
          const SizedBox(width: 10),
          Text('฿${cost.toStringAsFixed(cost == cost.roundToDouble() ? 0 : 2)}',
              style: baiJamjuree(size: 18, color: JuntraColors.gold)),
          const Spacer(),
          Text('เครดิต ฿${balance.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 12.5,
                color: low ? const Color(0xFFF5C542) : JuntraColors.textMuted,
              )),
        ],
      ),
    );
  }
}
