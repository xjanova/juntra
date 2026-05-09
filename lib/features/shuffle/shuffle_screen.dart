import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/sound/sound_service.dart';
import '../../shared/data/spreads.dart';
import '../../shared/data/tarot_deck.dart';
import '../../shared/widgets/gold_button.dart';
import '../../shared/widgets/starry_background.dart';
import '../../shared/widgets/tarot_card_widgets.dart';

/// ⭐ Screen 4 — Cinematic 5-phase tarot game.
///
/// Phases:
///   1. Question — user sets intention
///   2. Shuffle — face-down cards swirl in center for ~2s
///   3. Fan — full 78-card deck fanned (scrollable arc rows), user taps to pick
///   4. Travel — selected cards fly to center stack
///   5. Reveal — one card at a time, 3D Y-flip with gold rays + spotlight
///   6. Grid (final) — cards arranged in spread layout, then routes to /reading
///
/// This is the brand's signature interaction. Implementation favors
/// FAITHFUL TIMING and FEEL over micro-pixel parity with the React proto:
///   shuffle: 2000ms · travel: 800ms+80ms stagger · reveal: 2500ms each
class ShuffleScreen extends StatefulWidget {
  const ShuffleScreen({
    super.key, required this.spreadId, this.categoryId,
  });
  final String spreadId;
  final String? categoryId;

  @override
  State<ShuffleScreen> createState() => _ShuffleScreenState();
}

enum _Phase { question, shuffle, fan, travel, reveal, grid }

class _ShuffleScreenState extends State<ShuffleScreen>
    with TickerProviderStateMixin {
  _Phase _phase = _Phase.question;
  // Captured for telemetry — sent with /v1/fortune/draw payload later.
  String _question = ''; // ignore: unused_field
  final _picked = <int>[];
  int _revealIdx = 0;
  late final Spread _spread = spreads.firstWhere(
    (s) => s.id == widget.spreadId,
    orElse: () => spreads.first,
  );

  late final AnimationController _shuffleCtrl;
  late final AnimationController _revealCtrl;

  @override
  void initState() {
    super.initState();
    _shuffleCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2000),
    );
    _revealCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100),
    );
  }

  @override
  void dispose() {
    _shuffleCtrl.dispose();
    _revealCtrl.dispose();
    super.dispose();
  }

  Future<void> _startShuffle() async {
    // Idempotent: rapid double-tap on "เริ่มสับไพ่" must NOT spawn a second
    // shuffle controller or queue a second phase transition.
    if (_phase != _Phase.question) return;
    setState(() => _phase = _Phase.shuffle);
    HapticFeedback.mediumImpact();
    SoundService.instance.shuffle();
    _shuffleCtrl.forward(from: 0);
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    if (!mounted) return;
    setState(() => _phase = _Phase.fan);
  }

  void _onPickCard(int deckIndex) {
    if (_picked.contains(deckIndex) || _picked.length >= _spread.cards) return;
    HapticFeedback.lightImpact();
    SoundService.instance.cardPick();
    setState(() => _picked.add(deckIndex));
    if (_picked.length == _spread.cards) {
      _enterTravel();
    }
  }

  Future<void> _enterTravel() async {
    setState(() => _phase = _Phase.travel);
    await Future<void>.delayed(
      Duration(milliseconds: 800 + _picked.length * 80),
    );
    if (!mounted) return;
    setState(() {
      _phase = _Phase.reveal;
      _revealIdx = 0;
    });
    SoundService.instance.reveal();
    await _revealCtrl.forward(from: 0);
  }

  Future<void> _nextReveal() async {
    // Guard rapid double-taps + late callbacks from a previous flip
    // animation that is still running.
    if (_revealCtrl.isAnimating) return;
    if (_revealIdx + 1 >= _picked.length) {
      SoundService.instance.complete();
      setState(() => _phase = _Phase.grid);
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      if (!mounted) return;
      context.pushReplacement('${Routes.reading}?spread=${_spread.id}');
      return;
    }
    setState(() => _revealIdx += 1);
    SoundService.instance.reveal();
    await _revealCtrl.forward(from: 0);
    if (!mounted) return; // controller may complete after pop
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const StarryBackground(density: 70, intensity: 1.0),
          SafeArea(
            child: Stack(
              children: [
                _buildBackButton(),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: switch (_phase) {
                    _Phase.question => _buildQuestionPhase(),
                    _Phase.shuffle => _buildShufflePhase(),
                    _Phase.fan => _buildFanPhase(),
                    _Phase.travel => _buildTravelPhase(),
                    _Phase.reveal => _buildRevealPhase(),
                    _Phase.grid => _buildGridPhase(),
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: JuntraColors.gold, size: 28),
            onPressed: () => context.pop(),
          ),
          const Spacer(),
          if (_phase == _Phase.fan)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                '${_picked.length}/${_spread.cards}',
                style: baiJamjuree(size: 16, color: JuntraColors.gold),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Phase 1: Question ──────────────────────────────────────
  Widget _buildQuestionPhase() {
    return Padding(
      key: const ValueKey('q'),
      padding: const EdgeInsets.fromLTRB(24, 60, 24, 32),
      child: Column(
        children: [
          const Spacer(),
          Text('ก่อนเริ่ม...', style: baiJamjuree(size: 16, color: JuntraColors.gold)),
          const SizedBox(height: 8),
          Text('ลูกอยากรู้เรื่องอะไร?', style: baiJamjuree(size: 26)),
          const SizedBox(height: 16),
          const Text(
            'ตั้งใจให้แน่ ก่อนแม่หมอเริ่มสับไพ่ให้ลูก',
            style: TextStyle(fontSize: 13, color: JuntraColors.textMuted),
          ),
          const SizedBox(height: 28),
          TextField(
            onChanged: (v) => _question = v,
            maxLines: 3, minLines: 3,
            style: const TextStyle(color: JuntraColors.textCream, fontSize: 14),
            cursorColor: JuntraColors.gold,
            decoration: InputDecoration(
              hintText: 'เช่น ความสัมพันธ์กับคนที่กำลังคุยอยู่จะไปถึงไหน?',
              hintStyle: const TextStyle(color: JuntraColors.textFaint, fontSize: 13),
              filled: true,
              fillColor: JuntraColors.bgPurpleDeep.withValues(alpha: 0.6),
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: JuntraColors.purple.withValues(alpha: 0.4)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: JuntraColors.gold, width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: JuntraColors.purple.withValues(alpha: 0.4)),
              ),
            ),
          ),
          const Spacer(),
          GoldButton(
            label: 'เริ่มสับไพ่',
            icon: const Text('✦', style: TextStyle(fontSize: 16)),
            size: GoldButtonSize.lg,
            onPressed: _startShuffle,
          ),
        ],
      ),
    );
  }

  // ─── Phase 2: Shuffle ───────────────────────────────────────
  Widget _buildShufflePhase() {
    final rng = math.Random(7);
    return Center(
      key: const ValueKey('s'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 320, height: 320,
            child: AnimatedBuilder(
              animation: _shuffleCtrl,
              builder: (_, __) {
                return Stack(
                  alignment: Alignment.center,
                  children: List.generate(14, (i) {
                    final t = _shuffleCtrl.value * 6.28 + i * 0.45;
                    final r = 50 + math.sin(t * 0.7) * 30;
                    final ang = t + rng.nextDouble() * 0.4;
                    return Transform.translate(
                      offset: Offset(math.cos(ang) * r, math.sin(ang) * r),
                      child: Transform.rotate(
                        angle: ang * 0.3,
                        child: const CardBack(width: 60, height: 100),
                      ),
                    );
                  }),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          Text('แม่หมอกำลังสับไพ่...',
              style: baiJamjuree(size: 16, color: JuntraColors.gold)),
        ],
      ),
    );
  }

  // ─── Phase 3: Fan ───────────────────────────────────────────
  // Full 78-card layout: 10 rows of 8 (last row 6) so every card stays
  // tappable. Total stack height ~830px exceeds any phone viewport, so the
  // area is wrapped in a SingleChildScrollView — the seeker scrolls down to
  // browse the rest of the deck.
  static const _fanRowSizes = [8, 8, 8, 8, 8, 8, 8, 8, 8, 6]; // sums to 78
  static const _fanRowSpacing = 78.0;
  static const _fanRowTopOffset = 60.0;
  static const _fanCardW = 60.0;
  static const _fanCardH = 98.0;

  Widget _buildFanPhase() {
    final stackHeight = _fanRowTopOffset
        + _fanRowSpacing * _fanRowSizes.length
        + _fanCardH; // tail room so the last row isn't clipped
    return Column(
      key: const ValueKey('f'),
      children: [
        const SizedBox(height: 80),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              Text('เลือกไพ่ ${_spread.cards} ใบจากสำรับเต็ม 78 ใบ',
                  style: baiJamjuree(size: 20)),
              const SizedBox(height: 6),
              const Text(
                'แตะไพ่ที่หัวใจดึงดูดให้ลูก · เลื่อนลงเพื่อดูเพิ่ม',
                style: TextStyle(fontSize: 12, color: JuntraColors.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: LayoutBuilder(
            builder: (_, constraints) {
              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: SizedBox(
                  height: stackHeight,
                  child: Stack(
                    alignment: Alignment.topCenter,
                    clipBehavior: Clip.none,
                    children: List.generate(78, (deckIndex) {
                      final picked = _picked.contains(deckIndex);
                      final pickOrder =
                          picked ? _picked.indexOf(deckIndex) + 1 : 0;
                      return _buildFanCard(
                        deckIndex: deckIndex,
                        constraints: constraints,
                        picked: picked,
                        pickOrder: pickOrder,
                      );
                    }),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFanCard({
    required int deckIndex,
    required BoxConstraints constraints,
    required bool picked,
    required int pickOrder,
  }) {
    var row = 0;
    var idxInRow = deckIndex;
    for (var i = 0; i < _fanRowSizes.length; i++) {
      if (idxInRow < _fanRowSizes[i]) { row = i; break; }
      idxInRow -= _fanRowSizes[i];
    }
    final rowCount = _fanRowSizes[row];

    final t = rowCount == 1 ? 0.5 : idxInRow / (rowCount - 1.0);
    final ang = (t - 0.5) * (math.pi * 0.32);
    const radius = 280.0;
    final cx = constraints.maxWidth / 2;
    final cy = _fanRowTopOffset + row * _fanRowSpacing;
    final x = cx + math.sin(ang) * radius;
    final y = cy + (1 - math.cos(ang)) * 30;
    final rot = ang;

    return Positioned(
      left: x - _fanCardW / 2,
      top: y - 30 + (picked ? -22 : 0),
      child: GestureDetector(
        onTap: () => _onPickCard(deckIndex),
        child: AnimatedScale(
          scale: picked ? 1.18 : 1.0,
          duration: const Duration(milliseconds: 250),
          child: Transform.rotate(
            angle: rot,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Opacity(
                  opacity: picked ? 1.0 : 0.95,
                  child: const CardBack(width: _fanCardW, height: _fanCardH),
                ),
                if (picked)
                  Positioned(
                    top: -22, left: 0, right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: JuntraColors.goldButtonGradient,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$pickOrder',
                          style: const TextStyle(
                            color: JuntraColors.bgPurpleDeep,
                            fontSize: 11, fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Phase 4: Travel ────────────────────────────────────────
  Widget _buildTravelPhase() {
    return Center(
      key: const ValueKey('t'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 100, height: 160,
            child: Stack(
              alignment: Alignment.center,
              children: List.generate(_picked.length, (i) {
                return Transform.translate(
                  offset: Offset(i * 4.0, -i * 3.0),
                  child: const CardBack(width: 90, height: 145),
                );
              }),
            ),
          ),
          const SizedBox(height: 16),
          Text('ไพ่ของลูกพร้อมแล้ว',
              style: baiJamjuree(size: 14, color: JuntraColors.gold)),
        ],
      ),
    );
  }

  // ─── Phase 5: Reveal ────────────────────────────────────────
  Widget _buildRevealPhase() {
    final card = tarotDeck[_picked[_revealIdx]];
    final positionLabel = _revealIdx < _spread.positions.length
        ? _spread.positions[_revealIdx] : '';

    return Center(
      key: ValueKey('r$_revealIdx'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Spotlight + rotating gold rays
          SizedBox(
            width: 280, height: 360,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _GoldRays(),
                AnimatedBuilder(
                  animation: _revealCtrl,
                  builder: (_, __) {
                    final v = _revealCtrl.value;
                    final scale = 0.3 + Curves.easeOutBack.transform(v.clamp(0.0, 1.0)) * 0.7;
                    final flipAngle = (1 - v) * math.pi;
                    return Transform.scale(
                      scale: scale.clamp(0.3, 1.0),
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.001)
                          ..rotateY(flipAngle),
                        child: flipAngle < math.pi / 2
                            ? CardFront(card: card, width: 180, height: 290)
                            : Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.rotationY(math.pi),
                                child: const CardBack(width: 180, height: 290),
                              ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              colors: [Color(0xFFFFE7A0), Color(0xFFF0C75E), Color(0xFFB8881F)],
            ).createShader(rect),
            child: Text(card.thai,
                style: baiJamjuree(size: 28, color: Colors.white)),
          ),
          const SizedBox(height: 4),
          Text('ใบที่ ${_revealIdx + 1} · $positionLabel',
              style: const TextStyle(
                fontSize: 12, color: JuntraColors.textMuted,
                letterSpacing: 1.4,
              )),
          const SizedBox(height: 28),
          GhostButton(
            label: _revealIdx + 1 == _picked.length
                ? 'ดูคำทำนายเต็ม →' : 'ใบถัดไป →',
            onPressed: _nextReveal,
          ),
        ],
      ),
    );
  }

  // ─── Phase 6: Grid (brief landing then route) ──────────────
  Widget _buildGridPhase() {
    return Center(
      key: const ValueKey('g'),
      child: Wrap(
        spacing: 8, runSpacing: 8,
        alignment: WrapAlignment.center,
        children: _picked.map((i) {
          return CardFront(card: tarotDeck[i], width: 72, height: 118);
        }).toList(),
      ),
    );
  }
}

class _GoldRays extends StatefulWidget {
  @override
  State<_GoldRays> createState() => _GoldRaysState();
}

class _GoldRaysState extends State<_GoldRays>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Transform.rotate(
        angle: _ctrl.value * math.pi * 2,
        child: CustomPaint(
          painter: _RaysPainter(),
          size: const Size(280, 360),
        ),
      ),
    );
  }
}

class _RaysPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          JuntraColors.gold.withValues(alpha: 0.5),
          JuntraColors.gold.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: c, radius: size.width / 2));
    for (var i = 0; i < 12; i++) {
      final ang = i * math.pi / 6;
      final p2 = c + Offset(math.cos(ang), math.sin(ang)) * size.width / 2;
      canvas.drawLine(c, p2, paint..strokeWidth = 12);
    }
  }

  @override
  bool shouldRepaint(covariant _RaysPainter old) => false;
}
