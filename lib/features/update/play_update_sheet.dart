import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/update/play_update_service.dart';
import '../../shared/widgets/gold_button.dart';

/// แจ้งว่ามีรุ่นใหม่บน Google Play — กด "อัปเดต" แล้ว Play เป็นคนทำต่อทั้งหมด
/// (หน้าตาเดียวกับ [UpdateDialog] ของช่อง APK แต่ไม่มีการดาวน์โหลดในแอพ)
class PlayUpdateSheet extends ConsumerStatefulWidget {
  const PlayUpdateSheet({super.key, required this.status});
  final PlayUpdateAvailable status;

  static Future<void> show(BuildContext ctx, PlayUpdateAvailable s) {
    return showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (_) => PlayUpdateSheet(status: s),
    );
  }

  @override
  ConsumerState<PlayUpdateSheet> createState() => _PlayUpdateSheetState();
}

class _PlayUpdateSheetState extends ConsumerState<PlayUpdateSheet> {
  bool _busy = false;

  Future<void> _update() async {
    if (_busy) return;
    setState(() => _busy = true);
    final svc = ref.read(playUpdateServiceProvider);
    await svc.startUpdate(widget.status);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF1A0F2E), Color(0xFF0A0414)],
          ),
          borderRadius: BorderRadius.circular(JuntraRadius.hero),
          border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.4)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'มีเวอร์ชันใหม่',
                style: TextStyle(
                  fontSize: 10,
                  color: JuntraColors.gold, fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text('จันทราพยากรณ์รุ่นใหม่พร้อมแล้ว',
                  style: baiJamjuree(size: 20), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text(
                'อัปเดตผ่าน Google Play เพื่อรับฟีเจอร์ใหม่และการแก้ไขล่าสุด',
                style: TextStyle(fontSize: 13, color: JuntraColors.textLavender, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              GoldButton(
                label: _busy ? 'กำลังเปิด Google Play...' : 'อัปเดตตอนนี้',
                icon: const Icon(Icons.system_update_alt_rounded),
                onPressed: _busy ? null : _update,
              ),
              const SizedBox(height: 8),
              GhostButton(
                label: 'ภายหลัง',
                onPressed: _busy
                    ? null
                    : () async {
                        await ref.read(playUpdateServiceProvider).dismiss(widget.status);
                        if (context.mounted) Navigator.of(context).pop();
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
