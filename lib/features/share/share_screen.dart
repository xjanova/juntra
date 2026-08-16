import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme.dart';

/// Screen 12 — แชร์คำทำนาย
///
/// 🔴 ของเดิมเป็นตารางปุ่ม 8 อันที่ **ไม่มี onTap สักปุ่ม** — เปิดจากหน้าผล
/// ทำนายที่เพิ่งจ่ายเงิน กดทุกปุ่มแล้วไม่มีอะไรเกิดขึ้น ต้องแตะพื้นหลังปิดเอง
/// เป็นทางตันที่เจอทันทีหลังจ่ายเงิน
///
/// ตอนนี้เหลือเฉพาะช่องทางที่ทำได้จริงด้วยของที่แอพมีอยู่แล้ว
/// (`url_launcher` + `Clipboard`) — Instagram / TikTok / บันทึกรูป ถูกถอดออก
/// เพราะต้องใช้ไลบรารีเพิ่มและยังทำไม่ได้ **ปุ่มที่กดไม่ได้แย่กว่าไม่มีปุ่ม**
class ShareScreen extends StatelessWidget {
  const ShareScreen({super.key, this.readingId});

  /// id ของคำทำนายที่จะแชร์ — ไม่มีก็แชร์ลิงก์เว็บกลางแทน
  final int? readingId;

  static const _host = 'https://xn--82c4af5bzdj.online';

  String get _url => readingId == null
      ? _host
      : '$_host/tarot/result/$readingId';

  String get _text => 'แม่หมอจันทราเปิดไพ่ให้ฉันแล้ว ✨ ลองดูดวงกันไหม';

  @override
  Widget build(BuildContext context) {
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
                    Text('แชร์คำทำนาย', style: baiJamjuree(size: 18)),
                    const SizedBox(height: 16),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 4,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 8,
                      children: [
                        _PlatformTile(
                          name: 'LINE',
                          icon: Icons.chat_bubble_outline,
                          color: const Color(0xFF06C755),
                          onTap: () => _open(
                            context,
                            'https://line.me/R/share?text='
                            '${Uri.encodeComponent('$_text $_url')}',
                          ),
                        ),
                        _PlatformTile(
                          name: 'Facebook',
                          icon: Icons.public,
                          color: const Color(0xFF1877F2),
                          onTap: () => _open(
                            context,
                            'https://www.facebook.com/sharer/sharer.php?u='
                            '${Uri.encodeComponent(_url)}',
                          ),
                        ),
                        _PlatformTile(
                          name: 'X',
                          icon: Icons.close,
                          color: Colors.black,
                          onTap: () => _open(
                            context,
                            'https://twitter.com/intent/tweet?text='
                            '${Uri.encodeComponent(_text)}&url=${Uri.encodeComponent(_url)}',
                          ),
                        ),
                        _PlatformTile(
                          name: 'คัดลอกลิงก์',
                          icon: Icons.link,
                          color: JuntraColors.gold,
                          onTap: () async {
                            await Clipboard.setData(ClipboardData(text: _url));
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('คัดลอกลิงก์แล้วค่ะ'),
                                backgroundColor: JuntraColors.bgPurpleDeep,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            if (context.mounted) context.pop();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, String url) async {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('เปิดแอพปลายทางไม่ได้ — ลองใช้ "คัดลอกลิงก์" แทนนะคะ'),
        backgroundColor: JuntraColors.bgPurpleDeep,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    context.pop();
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
    );
  }
}
