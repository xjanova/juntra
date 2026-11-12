import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../app/theme.dart';
import '../../core/voice/media_url.dart';
import 'room_visuals.dart';

/// ฉากผู้พยากรณ์บนหัวห้องแชท — คลิป idle ของห้อง (เว็บ `<x-oracle-stage>`)
///
/// - เล่นคลิปใน `media.loops` ต่อกันทีละคลิป วนไปเรื่อย ๆ · ปิดเสียงเสมอ และไม่แย่งเสียงแอพอื่น
/// - ภาพนิ่ง (still/ภาพห้อง) อยู่ข้างใต้ตลอด — ระหว่างโหลดคลิป/คลิปเสียก็ยังเห็นผู้พยากรณ์
/// - ไม่มีคลิป (เซิร์ฟเวอร์เก่า/ออฟไลน์) = ภาพนิ่งหายใจช้า ๆ แทน
/// - หยุดเล่นเมื่อ [active] เป็น false (ยุบหัวห้องตอนพิมพ์) · มีหน้าอื่นมาทับ · แอพอยู่เบื้องหลัง
class RoomStage extends StatefulWidget {
  const RoomStage({
    super.key,
    required this.roomKey,
    required this.loops,
    this.posterUrl,
    this.active = true,
  });

  final String roomKey;

  /// mp4 (H.264) เท่านั้น — RoomMedia กรองมาให้แล้ว
  final List<String> loops;
  final String? posterUrl;
  final bool active;

  @override
  State<RoomStage> createState() => _RoomStageState();
}

class _RoomStageState extends State<RoomStage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat(reverse: true);

  VideoPlayerController? _video;
  int _index = 0;
  int _gen = 0;
  int _failures = 0;
  bool _advancing = false;
  bool _foreground = true;
  bool _onTop = true;

  bool get _shouldPlay => widget.active && _foreground && _onTop;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.loops.isNotEmpty) _load(0);
  }

  @override
  void didUpdateWidget(RoomStage old) {
    super.didUpdateWidget(old);
    if (old.roomKey != widget.roomKey || !_sameList(old.loops, widget.loops)) {
      _disposeVideo();
      _failures = 0;
      if (widget.loops.isNotEmpty) _load(0);
      setState(() {});
    } else if (old.active != widget.active) {
      _sync();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final onTop = TickerMode.valuesOf(context).enabled;
    if (onTop != _onTop) {
      _onTop = onTop;
      _sync();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _gen++;
    _disposeVideo();
    _breath.dispose();
    super.dispose();
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _disposeVideo() {
    _gen++; // คลิปเก่าที่ initialize ค้างอยู่ห้ามกลับมาแทนห้องใหม่
    final v = _video;
    _video = null;
    v?.removeListener(_onTick);
    v?.dispose();
  }

  Future<void> _load(int index) async {
    final gen = ++_gen;
    final loops = widget.loops;
    if (loops.isEmpty) return;
    VideoPlayerController? next;
    try {
      // URL เพี้ยนจากเซิร์ฟเวอร์ต้องตกไปคลิปถัดไป ไม่ใช่ error หลุดออกจาก future ที่ไม่มีใคร await
      next = VideoPlayerController.networkUrl(
        Uri.parse(mediaUrl(loops[index % loops.length])),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await next.initialize();
      await next.setVolume(0);
      await next.setLooping(loops.length == 1);
    } catch (_) {
      await next?.dispose();
      if (!mounted || gen != _gen) return;
      // คลิปนี้เสีย — ข้ามไปคลิปถัดไป · เสียครบทุกคลิป = เหลือภาพนิ่ง
      _failures++;
      if (_failures < loops.length) unawaited(_load(index + 1));
      return;
    }
    if (!mounted || gen != _gen) {
      await next.dispose();
      return;
    }
    _failures = 0;
    final old = _video;
    next.addListener(_onTick);
    setState(() {
      _video = next;
      _index = index % loops.length;
    });
    old?.removeListener(_onTick);
    // ปล่อยตัวเก่าหลังตัวใหม่ขึ้นจอแล้ว — ไม่กระพริบเป็นจอดำระหว่างเปลี่ยนคลิป
    unawaited(old?.dispose());
    if (_shouldPlay) unawaited(next.play());
  }

  void _onTick() {
    final v = _video;
    if (v == null || widget.loops.length < 2 || _advancing) return;
    final value = v.value;
    final done =
        value.isCompleted ||
        (value.duration > Duration.zero &&
            value.position >= value.duration &&
            !value.isPlaying);
    if (!done) return;
    _advancing = true;
    _load(_index + 1).whenComplete(() => _advancing = false);
  }

  void _sync() {
    final v = _video;
    if (v != null && v.value.isInitialized) {
      _shouldPlay ? v.play() : v.pause();
    }
    if (_shouldPlay) {
      if (!_breath.isAnimating) _breath.repeat(reverse: true);
    } else {
      _breath.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _video;
    final ready = v != null && v.value.isInitialized && v.value.size.width > 0;
    return Stack(
      fit: StackFit.expand,
      children: [
        // ภาพนิ่ง (หายใจช้า ๆ เมื่อไม่มีคลิป)
        AnimatedBuilder(
          animation: _breath,
          builder: (_, child) => Transform.scale(
            scale: ready
                ? 1
                : 1 + 0.025 * Curves.easeInOut.transform(_breath.value),
            child: child,
          ),
          child: RoomImage(roomKey: widget.roomKey, imageUrl: widget.posterUrl),
        ),
        if (v != null)
          AnimatedOpacity(
            opacity: ready ? 1 : 0,
            duration: const Duration(milliseconds: 450),
            child: ready
                ? ClipRect(
                    child: FittedBox(
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: v.value.size.width,
                        height: v.value.size.height,
                        child: VideoPlayer(v),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        // ขอบล่างจางลงพื้นห้อง
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.transparent,
                  JuntraColors.bgDeepest,
                ],
                stops: [0, 0.55, 1],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
