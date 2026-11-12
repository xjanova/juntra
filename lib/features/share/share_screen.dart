import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/app_config_repository.dart';
import '../../core/api/fortune_repository.dart';
import '../../core/api/reading_engagement_repository.dart';
import 'share_link.dart';

/// Screen 12 — แชร์คำทำนาย
///
/// 🔴 ของเดิมเป็นตารางปุ่ม 8 อันที่ **ไม่มี onTap สักปุ่ม** — เปิดจากหน้าผล
/// ทำนายที่เพิ่งจ่ายเงิน กดทุกปุ่มแล้วไม่มีอะไรเกิดขึ้น ต้องแตะพื้นหลังปิดเอง
///
/// ตอนนี้เหลือ 3 ช่องทางเท่าเว็บ (LINE · Facebook · คัดลอกลิงก์ — เว็บไม่มี X แล้ว)
///
/// 🔴 ลิงก์หน้าผลของเว็บเปิดได้เฉพาะคำทำนายที่เจ้าของ "เปิดลิงก์แชร์" ไว้ — ของเดิมแชร์
/// `/tarot/result/{id}` ตรง ๆ เพื่อนที่กดลิงก์เจอ 403 ทุกครั้ง ตอนนี้:
///   - เซิร์ฟเวอร์มี `features.reading_share` → เปิดลิงก์ก่อน (`POST …/share {public:true}`)
///     แล้วใช้ลิงก์ที่ได้กลับมา
///   - เซิร์ฟเวอร์เก่า → ใช้ลิงก์เดิมเฉพาะเมื่อคำทำนายเปิดแชร์ไว้แล้ว ไม่งั้นแชร์ข้อความอย่างเดียว
class ShareScreen extends ConsumerStatefulWidget {
  const ShareScreen({super.key, this.readingId});

  /// id ของคำทำนายที่จะแชร์ — ไม่มีก็แชร์ลิงก์เว็บกลางแทน
  final int? readingId;

  @override
  ConsumerState<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends ConsumerState<ShareScreen> {
  /// ลิงก์ที่ตัดสินแล้ว (เปิดลิงก์ครั้งเดียวต่อการเปิดแผ่นนี้)
  ShareLink? _link;
  bool _busy = false;

  bool get _usesShareApi =>
      widget.readingId != null && ref.read(appConfigValueProvider).has('reading_share');

  /// รายละเอียดคำทำนาย (ถ้าหน้าผลโหลดไว้แล้ว) — ใช้ชื่อผู้อ่าน + สถานะแชร์ของเซิร์ฟเวอร์เก่า
  ReadingExtras? get _extras {
    final id = widget.readingId;
    if (id == null) return null;
    final detail = ref.read(readingDetailProvider(id)).valueOrNull;
    return detail == null ? null : ReadingExtras.fromReading(detail);
  }

  Future<ShareLink?> _resolve() async {
    final cached = _link;
    if (cached != null) return cached;
    final id = widget.readingId;
    if (id == null || !_usesShareApi) {
      return _link = shareLinkFor(readingId: id, share: _extras?.share);
    }
    setState(() => _busy = true);
    try {
      final repo = await ref.read(readingEngagementRepositoryProvider.future);
      final share = await repo.setShare(id, public: true);
      if (!mounted) return null;
      // หน้าผลต้องเห็นว่าลิงก์เปิดแล้ว (การ์ดแชร์บนหน้าผล)
      ref.invalidate(readingDetailProvider(id));
      return _link = shareLinkFor(readingId: id, share: share);
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('เปิดลิงก์แชร์ไม่สำเร็จ ตรวจสอบสัญญาณแล้วลองใหม่อีกครั้งนะคะ');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return null;
  }

  String get _text => shareMessage(
        readingId: widget.readingId,
        reader: _extras?.readerName ?? 'แม่หมอจันทรา',
      );

  @override
  Widget build(BuildContext context) {
    final id = widget.readingId;
    final shareApi = id != null && ref.watch(appConfigValueProvider).has('reading_share');
    final detail = id == null ? null : ref.watch(readingDetailProvider(id)).valueOrNull;
    final public = detail != null && ReadingExtras.fromReading(detail).share.public;
    final textOnly = id != null && !shareApi && !public;
    final willOpenLink = shareApi && !public && _link == null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () => context.pop(),
        child: Container(
          color: Colors.black.withValues(alpha: 0.7),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () {/* swallow */},
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Color(0xFF1A0F2E), Color(0xFF0A0414)],
                  ),
                  borderRadius: BorderRadius.circular(JuntraRadius.hero),
                  border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.4)),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 36, height: 4,
                        decoration: BoxDecoration(
                          color: JuntraColors.textFaint,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(widget.readingId == null ? 'แชร์จันทรา' : 'แชร์ไพ่ชุดนี้', style: baiJamjuree(size: 18)),
                      if (willOpenLink || textOnly) ...[
                        const SizedBox(height: 8),
                        Text(
                          willOpenLink
                              // เว็บเตือนแบบเดียวกันก่อนเปิดลิงก์ — คำทำนายมีพื้นดวง/อายุจากวันเกิด
                              ? 'แตะช่องทางแชร์ = เปิดลิงก์ของคำทำนายนี้ ใครที่ได้ลิงก์จะเห็นคำถาม ไพ่ และคำทำนายทั้งหมด ปิดกลับได้ที่หน้าผลทำนาย'
                              : 'คำทำนายนี้ยังเป็นของส่วนตัว — แชร์ได้เป็นข้อความ ไม่แนบลิงก์ของคำทำนาย',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11.5, color: JuntraColors.textMuted, height: 1.55),
                        ),
                      ],
                      const SizedBox(height: 16),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: _busy ? 0.45 : 1,
                        child: IgnorePointer(
                          ignoring: _busy,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _PlatformTile(
                                name: 'LINE',
                                icon: Icons.chat_bubble_outline,
                                color: const Color(0xFF06C755),
                                onTap: _shareLine,
                              ),
                              _PlatformTile(
                                name: 'Facebook',
                                icon: Icons.public,
                                color: const Color(0xFF1877F2),
                                onTap: _shareFacebook,
                              ),
                              _PlatformTile(
                                name: textOnly ? 'คัดลอกข้อความ' : 'คัดลอกลิงก์',
                                icon: textOnly ? Icons.copy_rounded : Icons.link,
                                color: JuntraColors.gold,
                                onTap: _copy,
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 18,
                        child: _busy
                            ? const Center(
                                child: SizedBox(
                                  width: 14, height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: JuntraColors.gold),
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _shareLine() async {
    final link = await _resolve();
    if (link == null || !mounted) return;
    final body = link.hasUrl ? '$_text ${link.url}' : _text;
    await _open('https://line.me/R/share?text=${Uri.encodeComponent(body)}');
  }

  Future<void> _shareFacebook() async {
    final link = await _resolve();
    if (link == null || !mounted) return;
    // Facebook แชร์ได้แต่ลิงก์ — คำทำนายส่วนตัว (เซิร์ฟเวอร์เก่า) แชร์หน้าแรกแทนลิงก์ที่เปิดไม่ได้
    final url = link.url ?? kSiteUrl;
    await _open('https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(url)}');
  }

  Future<void> _copy() async {
    final link = await _resolve();
    if (link == null || !mounted) return;
    await Clipboard.setData(ClipboardData(text: link.url ?? _text));
    if (!mounted) return;
    _snack(link.hasUrl ? 'คัดลอกลิงก์แล้วค่ะ' : 'คัดลอกข้อความแล้วค่ะ');
    context.pop();
  }

  Future<void> _open(String url) async {
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (!ok) {
      _snack('เปิดแอพปลายทางไม่ได้ — ลองใช้ "คัดลอก" แทนนะคะ');
      return;
    }
    context.pop();
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: JuntraColors.bgPurpleDeep,
      behavior: SnackBarBehavior.floating,
    ));
  }
}

class _PlatformTile extends StatelessWidget {
  const _PlatformTile({
    required this.name,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String name;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 24, color: JuntraColors.textCream),
            ),
            const SizedBox(height: 6),
            Text(name, style: const TextStyle(
              fontSize: 11, color: JuntraColors.textCream,
            )),
          ],
        ),
      ),
    );
  }
}
