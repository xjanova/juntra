import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/update/update_service.dart';
import '../../shared/widgets/gold_button.dart';

/// Bottom-sheet style update prompt.
///
/// Renders ONLY the markdown release notes + version label + download
/// progress. The upstream provider, repo URL, and APK URL never reach
/// this widget — see the UI separation contract in `update_service.dart`.
class UpdateDialog extends ConsumerStatefulWidget {
  const UpdateDialog({super.key, required this.status});
  final UpdateAvailable status;

  static Future<void> show(BuildContext ctx, UpdateAvailable s) {
    return showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      isDismissible: false,
      enableDrag: false,
      builder: (_) => UpdateDialog(status: s),
    );
  }

  @override
  ConsumerState<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<UpdateDialog> {
  StreamSubscription<UpdateProgress>? _sub;
  int _percent = 0;
  bool _downloading = false;
  String? _error;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _startDownload() async {
    setState(() {
      _downloading = true;
      _error = null;
      _percent = 0;
    });
    try {
      final svc = ref.read(updateServiceProvider);
      _sub = svc.downloadAndInstall(widget.status.info).listen(
        (p) => setState(() => _percent = p.percent),
        onError: (Object e) {
          setState(() {
            _downloading = false;
            _error = 'ดาวน์โหลดไม่สำเร็จ ลองใหม่อีกครั้ง';
          });
        },
        onDone: () {
          // OS installer takes over from here — leave the sheet open
          // so the user can re-tap if Android dismisses the prompt.
        },
      );
    } catch (e) {
      setState(() {
        _downloading = false;
        _error = e is UnsupportedError
            ? 'การอัปเดตอัตโนมัติรองรับเฉพาะ Android'
            : 'เกิดข้อผิดพลาด ลองใหม่อีกครั้ง';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.status.info;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        constraints: const BoxConstraints(maxHeight: 560),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xFF1A0F2E), Color(0xFF0A0414)],
          ),
          borderRadius: BorderRadius.circular(JuntraRadius.hero),
          border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.4)),
          boxShadow: const [
            BoxShadow(color: Color(0xCC000000), blurRadius: 32, offset: Offset(0, 12)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '✨ มีเวอร์ชันใหม่',
                style: TextStyle(
                  fontSize: 10, letterSpacing: 4,
                  color: JuntraColors.gold, fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'จันทราพยากรณ์ ${info.latestVersion}',
                style: baiJamjuree(size: 22),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              const Text(
                'พร้อมให้อัปเดต',
                style: TextStyle(
                  fontSize: 12,
                  color: JuntraColors.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SingleChildScrollView(
                  child: MarkdownBody(
                    data: info.releaseNotesMd.isEmpty
                        ? '_ปรับปรุงประสบการณ์โดยรวม + แก้บั๊กเล็กๆ น้อยๆ_'
                        : info.releaseNotesMd,
                    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                        .copyWith(
                      p: const TextStyle(
                        fontSize: 13, color: JuntraColors.textLavender, height: 1.55,
                      ),
                      h1: baiJamjuree(size: 16, color: JuntraColors.textCream),
                      h2: baiJamjuree(size: 15, color: JuntraColors.textCream),
                      listBullet: const TextStyle(
                        fontSize: 13, color: JuntraColors.textLavender,
                      ),
                    ),
                    onTapLink: (_, _, _) {/* never open links from notes */},
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_downloading) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _percent <= 0 ? null : _percent / 100,
                    minHeight: 8,
                    backgroundColor: JuntraColors.bgPurple.withValues(alpha: 0.4),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(JuntraColors.gold),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _percent <= 0
                      ? 'กำลังเชื่อมต่อเซิร์ฟเวอร์อัปเดต...'
                      : 'ดาวน์โหลด $_percent%',
                  style: const TextStyle(
                    fontSize: 12, color: JuntraColors.textMuted,
                  ),
                  textAlign: TextAlign.center,
                ),
              ] else ...[
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFFFF6B6B), fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                ],
                GoldButton(
                  label: 'อัปเดตตอนนี้',
                  icon: const Icon(Icons.download_rounded),
                  onPressed: _startDownload,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: GhostButton(
                        label: 'ภายหลัง',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GhostButton(
                        label: 'ข้ามเวอร์ชันนี้',
                        onPressed: () async {
                          await ref.read(updateServiceProvider)
                              .dismissVersion(info.latestVersion, info.latestBuild);
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
