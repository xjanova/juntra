import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/fortune_repository.dart';
import '../../core/api/reading_engagement_repository.dart';
import '../../core/auth/auth_state.dart';

/// ✨ เสียงเล่าคำทำนายพรีเมียม — ตามแบบ `premiumVoice()` บนหน้าผลของเว็บ
///
/// เว็บไม่มีคิวงานเบื้องหลัง เซิร์ฟเวอร์จึงอัดเสียงทีละบท "ตามจังหวะที่หน้าผลถาม"
/// (`POST …/voice/next` หนึ่งครั้ง = หนึ่งก้าว) จนสถานะเป็น ready/partial แล้วค่อยรวมเป็นไฟล์เดียว
///   - ถามต่อทันที (400 ms) เมื่อก้าวก่อนสำเร็จ · 5 วิเมื่อพลาด · พลาด 6 ครั้งติดหยุดถาม (ให้กดลองใหม่)
///   - แอพอยู่เบื้องหลัง = ไม่ถาม (เว็บก็ไม่ถามตอนแท็บซ่อน) และหยุดเสียงทันที
///   - ไม่ได้เสียงเลย = เซิร์ฟเวอร์คืนค่าพรีเมียมเอง หน้านี้แค่บอกลูกค้า
///
/// ไฟล์เสียงดาวน์โหลดด้วย dio ของ ApiClient (bearer) ลงไฟล์ชั่วคราว แล้วลบทิ้งเมื่อออกจากหน้า
class ReadingVoicePanel extends ConsumerStatefulWidget {
  const ReadingVoicePanel({
    super.key,
    required this.readingId,
    required this.premium,
    this.voice,
    this.reader = 'แม่หมอ',
  });

  final int readingId;
  final ReadingPremium premium;

  /// เสียงที่อัดเสร็จแล้ว (จากรายละเอียดคำทำนาย) — มี = ข้ามไปดาวน์โหลดเลย
  final ReadingVoice? voice;

  /// ชื่อสั้นของผู้อ่าน ("บุษบา" / "แม่หมอ")
  final String reader;

  @override
  ConsumerState<ReadingVoicePanel> createState() => _ReadingVoicePanelState();
}

enum _Stage { building, downloading, ready, failed, refunded, hidden }

class _ReadingVoicePanelState extends ConsumerState<ReadingVoicePanel>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  static const _maxMisses = 6;

  _Stage _stage = _Stage.building;
  VoiceBuild _build = const VoiceBuild(status: 'building');
  int _misses = 0;
  bool _busy = false;
  bool _foreground = true;
  bool _slow = false;
  bool _toggling = false;

  Timer? _tickTimer;
  Timer? _slowTimer;
  CancelToken? _download;

  AudioPlayer? _player;
  final _subs = <StreamSubscription<dynamic>>[];
  final _tempFiles = <String>[];
  PlayerState _playerState = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double? _dragging;
  List<VoiceChapter> _chapters = const [];

  /// เลื่อนออกนอกจอแล้วยังต้องเล่นต่อ — ListView ทิ้งวิดเจ็ตที่พ้นจอได้ ถ้าไม่ขอเก็บไว้
  /// เสียงจะดับและไฟล์ถูกลบทุกครั้งที่ลูกค้าเลื่อนลงไปอ่านคำทำนาย
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final voice = widget.voice;
    if (widget.premium.refunded) {
      _stage = _Stage.refunded;
    } else if (voice != null && voice.playable) {
      _chapters = voice.chapters;
      _stage = _Stage.downloading;
      // หลังเฟรมแรก — ไม่เรียก setState ระหว่าง initState
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchAudio());
    } else if (voice != null && voice.status == 'none') {
      _stage = _Stage.hidden;
    } else {
      _slowTimer = Timer(const Duration(seconds: 8), () {
        if (mounted) setState(() => _slow = true);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _tick());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tickTimer?.cancel();
    _slowTimer?.cancel();
    _download?.cancel();
    // รอตัวเล่นปล่อยไฟล์ก่อนลบ (Windows ลบไฟล์ที่ยังเปิดอยู่ไม่ได้)
    unawaited(_disposePlayer().whenComplete(() {
      for (final path in _tempFiles) { _deleteQuietly(path); }
    }));
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // เปิดหน้าอื่นทับ (กด "คุยต่อ" ไปห้องแชท / แผ่นแชร์) = หยุดเสียง ไม่ให้เล่นซ้อนกับหน้าใหม่
    if (ModalRoute.isCurrentOf(context) == false && _playerState == PlayerState.playing) {
      _player?.pause();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    // ไปเบื้องหลัง/ล็อกจอ = หยุดเสียง (ไม่เล่นค้างตอนลูกค้าไม่ได้อยู่ในแอพ)
    if (!_foreground && _playerState == PlayerState.playing) {
      _player?.pause();
    }
  }

  // ─── อัดเสียงทีละก้าว ─────────────────────────────────────────

  void _schedule(Duration after) {
    _tickTimer?.cancel();
    _tickTimer = Timer(after, _tick);
  }

  Future<void> _tick() async {
    if (!mounted || _busy || _stage != _Stage.building) return;
    if (!_foreground || ModalRoute.isCurrentOf(context) == false) {
      _schedule(const Duration(seconds: 3));
      return;
    }
    _busy = true;
    VoiceBuild? got;
    try {
      final repo = await ref.read(readingEngagementRepositoryProvider.future);
      if (!mounted) return;
      got = await repo.voiceNext(widget.readingId);
    } on ApiException catch (e) {
      // ไม่มีเส้นนี้ (เซิร์ฟเวอร์เก่า) / ไม่ใช่เจ้าของ = ไม่มีเสียงให้ฟัง ซ่อนเงียบ ๆ
      if (e.statusCode == 404 || e.statusCode == 403) {
        _busy = false;
        if (mounted) setState(() => _stage = _Stage.hidden);
        return;
      }
    } catch (_) {
      // สัญญาณสะดุด — นับเป็นพลาดหนึ่งครั้ง
    }
    _busy = false;
    if (!mounted) return;

    if (got == null) {
      _misses++;
    } else {
      _misses = 0;
      final b = got;
      setState(() => _build = b);
      if (b.wait) {
        _schedule(const Duration(seconds: 3));
        return;
      }
      if (b.ready) {
        if (b.voice != null && b.voice!.chapters.isNotEmpty) _chapters = b.voice!.chapters;
        setState(() => _stage = _Stage.downloading);
        await _fetchAudio(url: b.url);
        return;
      }
      if (b.none) {
        setState(() => _stage = b.refunded ? _Stage.refunded : _Stage.hidden);
        // คืนค่าพรีเมียมแล้ว — ยอดบนหน้าแรก/วอลเลตต้องกลับมาทันที
        if (b.refunded) {
          // ignore: unawaited_futures
          ref.read(authControllerProvider.notifier).refresh();
        }
        return;
      }
    }
    if (_misses >= _maxMisses) {
      setState(() => _stage = _Stage.failed);
      return;
    }
    _schedule(_misses > 0 ? const Duration(seconds: 5) : const Duration(milliseconds: 400));
  }

  void _retry() {
    _misses = 0;
    if (_build.ready || _chapters.isNotEmpty) {
      setState(() => _stage = _Stage.downloading);
      _fetchAudio(url: _build.url);
    } else {
      setState(() => _stage = _Stage.building);
      _tick();
    }
  }

  // ─── ดาวน์โหลด + เตรียมตัวเล่น ───────────────────────────────

  Future<void> _fetchAudio({String? url}) async {
    if (!mounted) return;
    final cancel = CancelToken();
    _download = cancel;
    String? path;
    try {
      final dir = await getTemporaryDirectory();
      if (!mounted || cancel.isCancelled) return;
      path = '${dir.path}${Platform.pathSeparator}juntra-voice-${widget.readingId}-'
          '${DateTime.now().millisecondsSinceEpoch}.mp3';
      _tempFiles.add(path);
      final repo = await ref.read(readingEngagementRepositoryProvider.future);
      if (!mounted || cancel.isCancelled) return;
      await repo.downloadVoice(widget.readingId, path, url: url, cancel: cancel);
      if (!mounted) return; // dispose ลบไฟล์ใน _tempFiles ให้แล้ว

      await _disposePlayer();
      if (!mounted) return;
      final player = AudioPlayer();
      _player = player;
      await player.setReleaseMode(ReleaseMode.stop);
      if (!mounted) return;
      await player.setSource(DeviceFileSource(path));
      if (!mounted) return;
      _subs.addAll([
        player.onPlayerStateChanged.listen((s) {
          if (mounted) setState(() => _playerState = s);
        }),
        player.onDurationChanged.listen((d) {
          if (mounted) setState(() => _duration = d);
        }),
        player.onPositionChanged.listen((p) {
          if (mounted && _dragging == null) setState(() => _position = p);
        }),
        player.onPlayerComplete.listen((_) {
          if (mounted) setState(() => _position = Duration.zero);
        }),
      ]);
      final d = await player.getDuration();
      if (!mounted) return;
      setState(() {
        if (d != null) _duration = d;
        _stage = _Stage.ready;
      });
    } catch (_) {
      if (!mounted || cancel.isCancelled) return;
      if (path != null) {
        _deleteQuietly(path);
        _tempFiles.remove(path);
      }
      setState(() => _stage = _Stage.failed);
    } finally {
      // การดาวน์โหลดอาจเขียนไฟล์หลัง dispose เริ่มเก็บกวาดไปแล้ว
      if ((!mounted || cancel.isCancelled) && path != null) _deleteQuietly(path);
      if (identical(_download, cancel)) _download = null;
    }
  }

  Future<void> _disposePlayer() async {
    final subscriptions = List<StreamSubscription<dynamic>>.from(_subs);
    _subs.clear();
    final old = _player;
    _player = null;
    for (final s in subscriptions) { await s.cancel(); }
    try { await old?.dispose(); } catch (_) { /* ยังต้องเก็บกวาดไฟล์แม้ native player ปิดไปแล้ว */ }
  }

  static void _deleteQuietly(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {/* ไฟล์ชั่วคราว — ระบบเก็บกวาดเองได้ */}
  }

  Future<void> _toggle() async {
    final p = _player;
    if (p == null || _toggling || !_foreground) return;
    setState(() => _toggling = true);
    try {
      if (_playerState == PlayerState.playing) {
        await p.pause();
      } else {
        await p.resume();
        if (!_foreground || !mounted) await p.pause();
      }
    } catch (_) {
      if (mounted) setState(() => _stage = _Stage.failed);
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  String? get _caption {
    if (_chapters.isEmpty) return null;
    final t = _position.inMilliseconds / 1000.0;
    for (final c in _chapters) {
      if (t >= c.start && t < c.end) return c.say.trim().isEmpty ? null : c.say.trim();
    }
    return null;
  }

  // ─── หน้าตา ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_stage == _Stage.hidden) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          gradient: JuntraColors.mysticHeroGradient,
          borderRadius: BorderRadius.circular(JuntraRadius.card),
          border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.45)),
          boxShadow: JuntraShadows.goldGlow,
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 250),
          alignment: Alignment.topCenter,
          child: switch (_stage) {
            _Stage.building => _buildingView(),
            _Stage.downloading => _waitingView('กำลังเตรียมเสียง${widget.reader}…'),
            _Stage.ready => _playerView(),
            _Stage.failed => _failedView(),
            _Stage.refunded => _refundedView(),
            _Stage.hidden => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }

  Widget _eyebrow() => Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: JuntraColors.gold.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(JuntraRadius.chip),
              border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.4)),
            ),
            child: Text('✨ พรีเมียม · เสียง${widget.reader}',
                style: const TextStyle(fontSize: 11, color: JuntraColors.goldLight, fontWeight: FontWeight.w600)),
          ),
        ],
      );

  Widget _buildingView() {
    final b = _build;
    final chapter = b.total > 0 ? ' · บทที่ ${(b.done + 1).clamp(1, b.total)}/${b.total}' : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _eyebrow(),
        const SizedBox(height: 10),
        Text('${widget.reader}กำลังอัดเสียงเล่าคำทำนายให้คุณ…$chapter',
            style: const TextStyle(fontSize: 13.5, color: JuntraColors.textCream, height: 1.5)),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            minHeight: 6,
            value: b.total > 0 ? b.progress.clamp(0.06, 1.0) : null,
            backgroundColor: Colors.white.withValues(alpha: 0.12),
            valueColor: const AlwaysStoppedAnimation(JuntraColors.gold),
          ),
        ),
        if (_slow) ...[
          const SizedBox(height: 8),
          const Text(
            'ใช้เวลาสักครู่ อ่านคำทำนายด้านล่างรอไปก่อนได้เลยค่ะ เสร็จแล้วตรงนี้จะพร้อมฟังเอง',
            style: TextStyle(fontSize: 11.5, color: JuntraColors.textMuted, height: 1.5),
          ),
        ],
      ],
    );
  }

  Widget _waitingView(String text) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eyebrow(),
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: JuntraColors.gold),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: JuntraColors.textLavender))),
            ],
          ),
        ],
      );

  Widget _playerView() {
    final total = _duration.inMilliseconds;
    final pos = (_dragging ?? _position.inMilliseconds.toDouble()).clamp(0.0, total > 0 ? total.toDouble() : 1.0);
    final playing = _playerState == PlayerState.playing;
    final caption = _caption;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _eyebrow(),
        const SizedBox(height: 10),
        Row(
          children: [
            Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _toggling ? null : _toggle,
                child: Ink(
                  width: 52, height: 52,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: JuntraColors.goldButtonGradient,
                    boxShadow: JuntraShadows.goldGlow,
                  ),
                  child: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: JuntraColors.bgPurpleDeep,
                    size: 30,
                    semanticLabel: playing ? 'หยุดเสียง' : 'ฟังเสียง',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('🎧 เสียง${widget.reader}เล่าคำทำนาย',
                      style: baiJamjuree(size: 15, color: JuntraColors.goldLight)),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      overlayShape: SliderComponentShape.noOverlay,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      activeTrackColor: JuntraColors.gold,
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                      thumbColor: JuntraColors.goldLight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Slider(
                        min: 0,
                        max: total > 0 ? total.toDouble() : 1.0,
                        value: total > 0 ? pos : 0,
                        onChanged: total > 0 ? (v) => setState(() => _dragging = v) : null,
                        onChangeEnd: total > 0
                            ? (v) async {
                                await _player?.seek(Duration(milliseconds: v.round()));
                                if (!mounted) return;
                                setState(() {
                                  _position = Duration(milliseconds: v.round());
                                  _dragging = null;
                                });
                              }
                            : null,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Text(_fmt(Duration(milliseconds: pos.round())),
                          style: const TextStyle(fontSize: 10.5, color: JuntraColors.textMuted)),
                      const Spacer(),
                      Text(_fmt(_duration), style: const TextStyle(fontSize: 10.5, color: JuntraColors.textMuted)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (caption != null) ...[
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              caption,
              key: ValueKey(caption),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: JuntraColors.textLavender, height: 1.55, fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ],
    );
  }

  Widget _failedView() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eyebrow(),
          const SizedBox(height: 10),
          const Text(
            'ตอนนี้โหลดเสียงเล่าคำทำนายไม่สำเร็จ ตรวจสอบสัญญาณแล้วลองใหม่อีกครั้งนะคะ — คำทำนายด้านล่างอ่านได้ครบตามเดิม',
            style: TextStyle(fontSize: 12.5, color: JuntraColors.textLavender, height: 1.55),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _retry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('ลองใหม่'),
            style: TextButton.styleFrom(foregroundColor: JuntraColors.gold),
          ),
        ],
      );

  Widget _refundedView() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eyebrow(),
          const SizedBox(height: 10),
          const Text(
            'ขออภัยค่ะ ระบบเสียงขัดข้องจนอัดเสียงเล่าไม่ได้ — คืนค่าพรีเมียมเป็นเครดิตให้แล้ว (คำทำนายยังอ่านได้ครบตามเดิม)',
            style: TextStyle(fontSize: 12.5, color: JuntraColors.textLavender, height: 1.55),
          ),
        ],
      );

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
