import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/api/chat_repository.dart';

/// วาดใหม่ทุกวินาที เฉพาะตัวเอง — ไม่ให้นาฬิกานับถอยหลังสั่งวาดทั้งหน้าแชท (ฟองข้อความ markdown)
/// ทุกวินาที · [running] = false หยุดนับ
class SecondTicker extends StatefulWidget {
  const SecondTicker({super.key, required this.builder, this.running = true});

  final Widget Function(BuildContext context, DateTime now) builder;
  final bool running;

  @override
  State<SecondTicker> createState() => _SecondTickerState();
}

class _SecondTickerState extends State<SecondTicker> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(SecondTicker old) {
    super.didUpdateWidget(old);
    if (old.running != widget.running) _sync();
  }

  void _sync() {
    _timer?.cancel();
    _timer = widget.running
        ? Timer.periodic(const Duration(seconds: 1), (_) {
            if (mounted) setState(() {});
          })
        : null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, DateTime.now());
}

/// ป้ายนาฬิกาบนหัวห้อง — เวลาถามต่อหลังเปิดไพ่ ([free] = false) หรือเวลาถามฟรีหลังไพ่ฟรี ([free] = true)
///
/// ข้อความชุดเดียวกับเว็บ: ยังไม่เริ่ม = "ถามต่อได้ N นาที · เริ่มนับเมื่อถามคำถามแรก" ·
/// เริ่มแล้ว = "เหลือเวลาถามต่อ mm:ss" (สีเตือนเมื่อเหลือ ≤ warn นาที) · หมด = "หมดเวลาถามต่อแล้ว"
/// [onExpired] ถูกเรียกครั้งเดียวเมื่อนับถึงศูนย์บนเครื่อง (หน้าแชทปิดช่องพิมพ์ตาม)
class ChatClockChip extends StatefulWidget {
  const ChatClockChip({super.key, required this.clock, this.free = false, this.onExpired});

  final ChatClock clock;
  final bool free;
  final VoidCallback? onExpired;

  @override
  State<ChatClockChip> createState() => _ChatClockChipState();
}

class _ChatClockChipState extends State<ChatClockChip> {
  bool _fired = false;

  @override
  void didUpdateWidget(ChatClockChip old) {
    super.didUpdateWidget(old);
    if (!identical(old.clock, widget.clock)) _fired = false;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.clock;
    final running = c.started && !c.over;
    return SecondTicker(
      running: running,
      builder: (context, now) {
        final over = c.isOver(now);
        if (over && running && !_fired) {
          _fired = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onExpired?.call();
          });
        }
        final low = !widget.free ? c.isLow(now: now) : c.isLow(now: now, warnSeconds: 60);
        final String label;
        if (over) {
          label = widget.free ? 'ถามฟรีครบแล้ว' : 'หมดเวลาถามต่อแล้ว';
        } else if (!c.started) {
          label = widget.free
              ? 'ถามฟรีได้ ${c.minutes} นาที · เริ่มนับเมื่อถามคำถามแรก'
              : 'ถามต่อได้ ${c.minutes} นาที · เริ่มนับเมื่อถามคำถามแรก';
        } else {
          final left = ChatClock.format(c.secondsLeft(now));
          label = widget.free ? 'ถามฟรีอีก $left' : 'เหลือเวลาถามต่อ $left';
        }
        final color = over
            ? JuntraColors.textDim
            : low
                ? JuntraColors.rose
                : JuntraColors.goldLight;
        return Semantics(
          label: label,
          liveRegion: false,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: low ? 0.16 : 0.09),
              borderRadius: BorderRadius.circular(JuntraRadius.chip),
              border: Border.all(color: color.withValues(alpha: low ? 0.7 : 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hourglass_bottom_rounded, size: 13, color: color),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: color,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
