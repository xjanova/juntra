import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/report_repository.dart';
import 'gold_button.dart';

/// แผ่นรายงานเนื้อหาที่ AI สร้าง (คำทำนาย/ข้อความของแม่หมอ) — ไม่ต้องออกจากแอพ
///
/// Google Play บังคับ (AI-Generated Content policy): ผู้ใช้ต้องรายงาน/ติดธงเนื้อหาที่ไม่เหมาะสม
/// ได้จากในแอพ รายงานถึงแอดมินทาง Telegram และเข้าคิว "รายงานเนื้อหา AI" ในหลังบ้าน
class ReportContentSheet extends ConsumerStatefulWidget {
  const ReportContentSheet({super.key, required this.subject, required this.subjectId});
  final ReportSubject subject;
  final int subjectId;

  /// เปิดแผ่นรายงาน — คืน true เมื่อส่งสำเร็จ
  static Future<bool?> show(BuildContext context, {required ReportSubject subject, required int subjectId}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: JuntraColors.bgPurpleDeep,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ReportContentSheet(subject: subject, subjectId: subjectId),
    );
  }

  @override
  ConsumerState<ReportContentSheet> createState() => _ReportContentSheetState();
}

class _ReportContentSheetState extends ConsumerState<ReportContentSheet> {
  final _note = TextEditingController();
  ReportReason _reason = ReportReason.offensive;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return; // กดรัวไม่ส่งซ้ำ
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final repo = await ref.read(reportRepositoryProvider.future);
      final thanks = await repo.report(
        subject: widget.subject,
        subjectId: widget.subjectId,
        reason: _reason,
        note: _note.text,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(SnackBar(
        content: Text(thanks),
        backgroundColor: JuntraColors.bgPurpleDeep,
        behavior: SnackBarBehavior.floating,
      ));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = 'ส่งรายงานไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final what = widget.subject == ReportSubject.reading ? 'คำทำนายนี้' : 'ข้อความนี้ของแม่หมอ';
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: JuntraColors.gold.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('รายงาน$what', style: baiJamjuree(size: 18, color: JuntraColors.gold)),
              const SizedBox(height: 6),
              const Text(
                'เนื้อหาสร้างโดย AI อาจไม่เหมาะสมหรือผิดพลาดได้ — แจ้งทีมงานเพื่อตรวจสอบและปรับปรุง',
                style: TextStyle(fontSize: 12.5, color: JuntraColors.textMuted, height: 1.5),
              ),
              const SizedBox(height: 12),
              RadioGroup<ReportReason>(
                groupValue: _reason,
                onChanged: (v) {
                  if (v != null && !_sending) setState(() => _reason = v);
                },
                child: Column(
                  children: [
                    for (final r in ReportReason.values)
                      RadioListTile<ReportReason>(
                        value: r,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        activeColor: JuntraColors.gold,
                        title: Text(r.label, style: const TextStyle(fontSize: 14, color: JuntraColors.textCream)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _note,
                enabled: !_sending,
                maxLength: 1000,
                maxLines: 3,
                style: const TextStyle(color: JuntraColors.textCream, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'รายละเอียดเพิ่มเติม (ไม่บังคับ)',
                  hintStyle: const TextStyle(color: JuntraColors.textFaint),
                  filled: true,
                  fillColor: JuntraColors.bgDark2.withValues(alpha: 0.6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: JuntraColors.purple.withValues(alpha: 0.3)),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 12.5)),
              ],
              const SizedBox(height: 12),
              GoldButton(
                label: _sending ? 'กำลังส่ง...' : 'ส่งรายงาน',
                icon: const Icon(Icons.flag_outlined),
                onPressed: _sending ? null : _send,
              ),
              const SizedBox(height: 6),
              GhostButton(
                label: 'ยกเลิก',
                onPressed: _sending ? null : () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
