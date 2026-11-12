import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/fortune_repository.dart';
import '../../core/api/reading_engagement_repository.dart';
import '../../shared/data/juntra_art.dart';
import '../../shared/widgets/gold_button.dart';

/// 🌟 หลังจบคำทำนาย — ให้ดาว/รีวิว (เว็บ `x-reading-aftercare` ส่วน #review)
///
/// หนึ่งคำทำนาย = หนึ่งรีวิว แก้ได้ (แก้แล้วรอแอดมินอนุมัติใหม่) · ขึ้นหน้าแรกเว็บเมื่อ
/// ลูกค้ายอม + แอดมินอนุมัติ — กติกาอยู่ที่เซิร์ฟเวอร์ แอพแค่ส่งค่าแล้วแสดงที่ได้กลับมา
class ReadingReviewCard extends ConsumerStatefulWidget {
  const ReadingReviewCard({super.key, required this.readingId, this.initial, this.reader = 'แม่หมอ'});
  final int readingId;
  final ReadingReview? initial;
  final String reader;

  @override
  ConsumerState<ReadingReviewCard> createState() => _ReadingReviewCardState();
}

class _ReadingReviewCardState extends ConsumerState<ReadingReviewCard>
    with AutomaticKeepAliveClientMixin {
  static const _labels = ['แตะดาวเพื่อให้คะแนน', 'ยังไม่ตรงเลย', 'ตรงบางส่วน', 'พอใช้ได้', 'ตรงมาก', 'ตรงใจที่สุด'];

  late ReadingReview? _saved = widget.initial;
  late bool _editing = widget.initial == null;
  late int _rating = widget.initial?.rating ?? 0;
  late bool _allowPublic = widget.initial?.allowPublic ?? false;
  late final TextEditingController _message = TextEditingController(text: widget.initial?.message ?? '');
  bool _sending = false;
  bool _justSaved = false;
  bool _unsupported = false;
  String? _error;

  /// พิมพ์รีวิวค้างไว้แล้วเลื่อนจอ — ข้อความต้องไม่หาย
  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating < 1 || _sending) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final repo = await ref.read(readingEngagementRepositoryProvider.future);
      if (!mounted) return;
      final review = await repo.saveReview(
        widget.readingId,
        rating: _rating,
        message: _message.text,
        allowPublic: _allowPublic,
      );
      if (!mounted) return;
      setState(() {
        _saved = review;
        _editing = false;
        _justSaved = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _unsupported = e.statusCode == 404; _error = e.message; });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'บันทึกรีวิวไม่สำเร็จ ตรวจสอบสัญญาณแล้วลองใหม่อีกครั้งนะคะ');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_unsupported) return const SizedBox.shrink();
    return _AftercareBox(
      art: JuntraArt.review,
      eyebrow: 'คำทำนายนี้ตรงใจไหมคะ',
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        alignment: Alignment.topCenter,
        child: _editing || _saved == null ? _form() : _savedView(_saved!),
      ),
    );
  }

  Widget _savedView(ReadingReview r) {
    final note = r.allowPublic
        ? (r.approved == true ? 'รีวิวนี้ขึ้นหน้าแรกแล้ว' : 'รอแอดมินตรวจก่อนขึ้นหน้าแรก')
        : 'เก็บไว้ให้ทีมงานอ่านเท่านั้น ไม่ขึ้นหน้าแรก';
    final name = r.allowPublic && r.name != null ? ' · แสดงชื่อเป็น “${r.name}”' : '';
    return Column(
      children: [
        if (_justSaved) ...[
          Text('ขอบคุณที่บอก${widget.reader}นะคะ 💜 รีวิวของคุณบันทึกแล้ว',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: JuntraColors.gold)),
          const SizedBox(height: 6),
        ],
        _Stars(rating: r.rating, size: 26),
        if (r.message.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('“${r.message}”',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: JuntraColors.textLavender, fontStyle: FontStyle.italic, height: 1.55)),
        ],
        const SizedBox(height: 8),
        Text('$note$name',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11.5, color: JuntraColors.textMuted)),
        const SizedBox(height: 10),
        GhostButton(
          label: 'แก้รีวิว',
          full: false,
          onPressed: () => setState(() {
            _editing = true;
            _justSaved = false;
          }),
        ),
      ],
    );
  }

  Widget _form() {
    return Column(
      children: [
        _Stars(
          rating: _rating,
          size: 36,
          onTap: _sending ? null : (n) => setState(() => _rating = n),
        ),
        const SizedBox(height: 2),
        Text(_labels[_rating.clamp(0, 5)], style: const TextStyle(fontSize: 12.5, color: JuntraColors.textMuted)),
        const SizedBox(height: 12),
        TextField(
          controller: _message,
          enabled: !_sending,
          maxLines: 3,
          minLines: 2,
          maxLength: 500,
          style: const TextStyle(color: JuntraColors.textCream, fontSize: 14),
          cursorColor: JuntraColors.gold,
          decoration: InputDecoration(
            hintText: 'เล่าให้${widget.reader}ฟังหน่อย ตรงตรงไหน หรืออยากให้ปรับอะไร (ไม่บังคับ)',
            hintStyle: const TextStyle(color: JuntraColors.textFaint, fontSize: 12.5),
            counterStyle: const TextStyle(color: JuntraColors.textFaint, fontSize: 10.5),
            filled: true,
            fillColor: JuntraColors.bgDeepest.withValues(alpha: 0.5),
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(JuntraRadius.input),
              borderSide: const BorderSide(color: JuntraColors.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(JuntraRadius.input),
              borderSide: const BorderSide(color: JuntraColors.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(JuntraRadius.input),
              borderSide: const BorderSide(color: JuntraColors.gold),
            ),
          ),
        ),
        InkWell(
          onTap: _sending ? null : () => setState(() => _allowPublic = !_allowPublic),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _allowPublic,
                  onChanged: _sending ? null : (v) => setState(() => _allowPublic = v ?? false),
                  activeColor: JuntraColors.gold,
                  checkColor: JuntraColors.bgPurpleDeep,
                  side: const BorderSide(color: JuntraColors.line, width: 1.4),
                  visualDensity: VisualDensity.compact,
                ),
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'ยอมให้นำรีวิวนี้ขึ้นหน้าแรกของเว็บ (ไม่แสดงคำถามหรือคำทำนาย)',
                      style: TextStyle(fontSize: 12.5, color: JuntraColors.textLavender, height: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 4),
          Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFFFF8C8C), height: 1.5)),
        ],
        const SizedBox(height: 12),
        GoldButton(
          label: _sending ? 'กำลังบันทึก ⋯' : 'ส่งรีวิว',
          disabled: _rating < 1 || _sending,
          onPressed: _submit,
        ),
        if (_saved != null && !_sending)
          TextButton(
            onPressed: () => setState(() {
              _editing = false;
              _error = null;
              _rating = _saved!.rating;
              _allowPublic = _saved!.allowPublic;
              _message.text = _saved!.message;
            }),
            child: const Text('ยกเลิกการแก้', style: TextStyle(color: JuntraColors.textFaint)),
          ),
      ],
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.rating, this.size = 30, this.onTap});
  final int rating;
  final double size;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 1; i <= 5; i++)
          Semantics(
            button: onTap != null,
            selected: rating == i,
            label: '$i ดาว',
            child: InkResponse(
              onTap: onTap == null ? null : () => onTap!(i),
              radius: size * 0.7,
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(
                  Icons.star_rounded,
                  size: size,
                  color: i <= rating ? JuntraColors.gold : JuntraColors.gold.withValues(alpha: 0.22),
                  shadows: i <= rating
                      ? [Shadow(color: JuntraColors.gold.withValues(alpha: 0.45), blurRadius: 14)]
                      : null,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 🔗 เปิด/ปิดลิงก์แชร์ (เว็บ `x-reading-aftercare` ส่วน #share)
///
/// ค่าเริ่มต้นปิด (เป็นของส่วนตัว) · เปิดแล้วใครได้ลิงก์ก็เห็นคำถาม ไพ่ คำทำนาย รวมพื้นดวง
/// และอายุจากวันเกิด — จึงถามยืนยันก่อนเปิดทุกครั้ง ปิดกลับไม่ต้องถาม (คืนความเป็นส่วนตัว)
class ReadingShareCard extends ConsumerStatefulWidget {
  const ReadingShareCard({super.key, required this.readingId, required this.initial});
  final int readingId;
  final ReadingShare initial;

  @override
  ConsumerState<ReadingShareCard> createState() => _ReadingShareCardState();
}

class _ReadingShareCardState extends ConsumerState<ReadingShareCard> {
  late bool _public = widget.initial.public;
  bool _busy = false;
  String? _error;
  bool _unsupported = false;

  @override
  void didUpdateWidget(covariant ReadingShareCard old) {
    super.didUpdateWidget(old);
    // หน้าแชร์เปิดลิงก์ให้แล้ว (รายละเอียดคำทำนายโหลดใหม่) — ตามค่าจากเซิร์ฟเวอร์
    if (!_busy && old.initial.public != widget.initial.public) _public = widget.initial.public;
  }

  Future<void> _set(bool public) async {
    if (_busy) return;
    setState(() => _busy = true);
    if (public) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          backgroundColor: JuntraColors.bgPurpleDeep,
          title: Text('เปิดลิงก์แชร์?', style: baiJamjuree(size: 18, color: JuntraColors.gold)),
          content: const Text(
            'ใครที่ได้ลิงก์จะเห็นคำถาม ไพ่ และคำทำนายทั้งหมด รวมพื้นดวงและอายุจากวันเกิดของคุณ ปิดกลับได้ทุกเมื่อ',
            style: TextStyle(fontSize: 13.5, color: JuntraColors.textLavender, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: const Text('ยังไม่เปิด', style: TextStyle(color: JuntraColors.textMuted)),
            ),
            TextButton(
              onPressed: () => Navigator.of(d).pop(true),
              child: const Text('เปิดลิงก์', style: TextStyle(color: JuntraColors.gold, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (ok != true) { setState(() => _busy = false); return; }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = await ref.read(readingEngagementRepositoryProvider.future);
      if (!mounted) return;
      final share = await repo.setShare(widget.readingId, public: public);
      if (!mounted) return;
      setState(() => _public = share.public);
      ref.invalidate(readingDetailProvider(widget.readingId));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _unsupported = e.statusCode == 404; _error = e.message; });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'เปลี่ยนการแชร์ไม่สำเร็จ ตรวจสอบสัญญาณแล้วลองใหม่อีกครั้งนะคะ');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_unsupported) return const SizedBox.shrink();
    return _AftercareBox(
      eyebrow: 'แชร์ไพ่ชุดนี้',
      child: Column(
        children: [
          Text(
            _public
                ? 'ใครมีลิงก์ก็เปิดดูไพ่และคำทำนายนี้ได้ (ไม่ต้องล็อกอิน)'
                : 'ตอนนี้คำทำนายนี้เป็นของส่วนตัว เห็นได้แค่คุณ — ถ้าเปิดลิงก์แชร์ ใครที่ได้ลิงก์จะเห็นคำถาม ไพ่ และคำทำนายทั้งหมด ปิดกลับได้ทุกเมื่อ',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12.5, color: JuntraColors.textLavender, height: 1.6),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12.5, color: Color(0xFFFF8C8C))),
          ],
          const SizedBox(height: 12),
          if (_public) ...[
            GoldButton(
              label: 'แชร์ลิงก์',
              icon: const Icon(Icons.share_outlined),
              disabled: _busy,
              onPressed: () => context.push('${Routes.share}?id=${widget.readingId}'),
            ),
            TextButton(
              onPressed: _busy ? null : () => _set(false),
              child: Text(
                _busy ? 'กำลังปิดลิงก์ ⋯' : 'ปิดลิงก์แชร์ (กลับเป็นส่วนตัว)',
                style: const TextStyle(color: JuntraColors.textFaint, decoration: TextDecoration.underline),
              ),
            ),
          ] else
            GhostButton(
              label: _busy ? 'กำลังเปิดลิงก์ ⋯' : 'เปิดลิงก์แชร์',
              icon: const Icon(Icons.link_rounded),
              onPressed: _busy ? null : () => _set(true),
            ),
        ],
      ),
    );
  }
}

/// กรอบการ์ดหลังจบคำทำนาย — ภาพประกอบ (ไม่มีไฟล์ = ไม่มีภาพ) + ป้ายหัว + เนื้อหา
class _AftercareBox extends StatelessWidget {
  const _AftercareBox({required this.eyebrow, required this.child, this.art});
  final String eyebrow;
  final Widget child;
  final String? art;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(JuntraRadius.hero),
        border: Border.all(color: JuntraColors.lineSoft),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x1F6A3BD6), Color(0x0007041A)],
        ),
      ),
      child: Column(
        children: [
          if (art != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset(
                  art!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(JuntraRadius.chip),
              border: Border.all(color: JuntraColors.line),
            ),
            child: Text(eyebrow, style: const TextStyle(fontSize: 11.5, color: JuntraColors.gold, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
