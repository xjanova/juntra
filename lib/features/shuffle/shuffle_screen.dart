import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:intl/intl.dart';

import '../../core/api/tarot_packages_repository.dart';
import '../../core/astronomy/birth_data_store.dart';
import '../../core/api/idempotency.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/fortune_repository.dart';
import '../../core/api/tarot_catalog_repository.dart';
import '../../core/auth/auth_state.dart';
import '../../core/sound/sound_service.dart';
import '../../shared/data/tarot_deck.dart';
import '../../shared/widgets/gold_button.dart';
import '../../shared/widgets/starry_background.dart';
import '../../shared/widgets/tarot_card_widgets.dart';
import '../../shared/format/credits.dart';
import '../../core/app_channel.dart';
import '../wallet/play_credits_panel.dart';

/// ⭐ Screen 4 — Cinematic 5-phase tarot game.
///
/// Phases:
///   1. Question — user sets intention
///   2. Shuffle — face-down cards swirl in center for ~2s
///   3. Fan — full 78-card deck fanned (scrollable arc rows), user taps to pick
///   4. Travel — selected cards fly to center stack
///   5. Reveal — one card at a time, 3D Y-flip with gold rays + spotlight
///   6. Grid — cards arranged in spread layout (brief landing)
///   7. Saving — POST /v1/history/readings, debits wallet, AI interprets
///
/// This is the brand's signature interaction. Implementation favors
/// FAITHFUL TIMING and FEEL over micro-pixel parity with the React proto:
///   shuffle: 2000ms · travel: 800ms+80ms stagger · reveal: 2500ms each
///
/// For the **3-card** and **Celtic Cross** spreads the final action sends
/// the picked cards (with random reversed flags) to juntraweb which
/// debits the wallet, runs FortuneAiService, and returns a persisted
/// Reading id — we then `pushReplacement('/reading?id=<id>')`. For all
/// other (not-yet-supported on backend) spreads we fall back to the
/// legacy client-side sample reading so the cinematic still completes.
class ShuffleScreen extends ConsumerStatefulWidget {
  const ShuffleScreen({
    super.key, required this.spreadId, this.categoryId, this.initialQuestion,
  });
  final String spreadId;
  final String? categoryId;
  final String? initialQuestion;

  @override
  ConsumerState<ShuffleScreen> createState() => _ShuffleScreenState();
}

enum _Phase { question, shuffle, fan, travel, reveal, grid, saving }

class _ShuffleScreenState extends ConsumerState<ShuffleScreen>
    with TickerProviderStateMixin {
  _Phase _phase = _Phase.question;
  /// กันคิดเงินซ้ำ: การเปิดไพ่หนึ่งครั้งใช้คีย์เดียวตลอด รวมถึงตอนกดลองใหม่
  final _attempt = IdempotentAttempt('tarot');

  /// กองที่เซิร์ฟเวอร์สับให้สำหรับเกมนี้ — null = ยังไม่ได้ขอ / ขอไม่สำเร็จ
  ///
  /// 🔴 ก่อนหน้านี้ไม่มีสิ่งนี้เลย: ช่องที่ k บนพัดคือ `tarotDeck[k]` เสมอ
  /// ช่องซ้ายบนสุดจึงเป็น The Fool ตลอดกาล และหัวกลับถูกสุ่มในเครื่องที่ 30%
  /// (เว็บใช้ 50%) แล้วส่งขึ้นไปให้เซิร์ฟเวอร์เชื่อทั้งดุ้น
  TarotDeal? _deal;
  /// Web card-art catalog (faces + back) resolved in [build]; empty until the
  /// จันทรา.online catalog loads, at which point cards swap to their real art.
  TarotCatalog _catalog = TarotCatalog.empty;
  // Captured for telemetry — sent with /v1/fortune/draw payload later.
  late String _question = (widget.initialQuestion ?? '').trim();
  final _picked = <int>[];
  // Reversed flag per pick, decided at reveal time. Stable RNG seeded
  // with picks order + DateTime micro so two consecutive readings of
  // the same spread don't produce identical orientations.
  final _reversed = <bool>[];
  int _revealIdx = 0;
  /// แพ็กเกจของเกมนี้ (จากเซิร์ฟเวอร์ ชุดเดียวกับเว็บ) — ตรึงค่าแรกที่ได้ไว้ตลอดเกม
  /// หลังบ้านปรับราคา/ตำแหน่งระหว่างที่ลูกค้ากำลังเล่น ต้องไม่ทำให้จำนวนใบเปลี่ยนกลางเกม
  TarotPackage? _package;
  TarotPackage get _pkg => _package!;

  /// วันเกิด (ไม่บังคับ) — แพ็กเกจที่ผสานดวงวันเกิด (Celtic · 12 เดือน · คุณไสย) เหมือนเว็บ
  DateTime? _birthDate;
  bool _birthDefaulted = false;

  /// ข้อความผิดพลาดล่าสุดตอนบันทึก — หน้าจอโชว์ปุ่ม "ลองอีกครั้ง" (เดิมค้างอยู่ที่ไพ่โดยไม่มีทางไปต่อ)
  String? _lastError;

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
    // Self-heal the web card-art catalog: if it loaded empty earlier (e.g. the
    // app was first opened while the จันทรา.online catalog endpoint was briefly
    // unreachable), force a fresh fetch now so real card faces appear this game
    // — no manual app restart needed.
    Future.microtask(() {
      if (!mounted) return;
      final empty = ref
          .read(tarotCatalogProvider)
          .maybeWhen(data: (c) => c.isEmpty, orElse: () => false);
      if (empty) ref.invalidate(tarotCatalogProvider);
    });
  }

  /// ช่องคำถาม — เติมคำถามจากแชทให้ (ถ้ามี) · dispose พร้อมหน้า
  late final TextEditingController _questionCtrl = TextEditingController(text: _question);

  @override
  void dispose() {
    _questionCtrl.dispose();
    _shuffleCtrl.dispose();
    _revealCtrl.dispose();
    super.dispose();
  }

  Future<void> _startShuffle() async {
    // Idempotent: rapid double-tap on "เริ่มสับไพ่" must NOT spawn a second
    // shuffle controller or queue a second phase transition.
    if (_phase != _Phase.question) return;

    // เช็คสิทธิ์ก่อนให้เล่นซีน 1–2 นาที — ของเดิมเช็คตอนจบ แขกจึงต้องสับไพ่
    // จนครบ (เซลติก 10 ใบ) แล้วค่อยโดนเด้ง แล้วต้องเริ่มใหม่ทั้งหมด
    if (ref.read(authControllerProvider) is! AuthAuthenticated) {
      _showLoginNeededSheet();
      return;
    }

    setState(() => _phase = _Phase.shuffle);

    // ขอกองที่เซิร์ฟเวอร์สับให้ — ทำระหว่างแอนิเมชันสับ ผู้ใช้จึงไม่รู้สึกว่ารอ
    // ถ้าขอไม่ได้ (ออฟไลน์) ตกไปสับในเครื่องแทน ดีกว่าปล่อยให้เรียงเดิมตลอดกาล
    () async {
      try {
        final repo = await ref.read(tarotCatalogRepositoryProvider.future);
        final deal = await repo.deal();
        if (mounted && deal != null && deal.cards.isNotEmpty) {
          setState(() => _deal = deal);
        }
      } catch (_) {
        // เงียบไว้ — มี fallback ในเครื่องอยู่แล้ว
      }
    }();
    HapticFeedback.mediumImpact();
    SoundService.instance.shuffle();
    _shuffleCtrl.forward(from: 0);
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    if (!mounted) return;
    setState(() => _phase = _Phase.fan);
  }

  void _onPickCard(int slotIndex) {
    // แตะใบที่เลือกไว้แล้ว = ถอดออก — ของเดิมเงียบเฉย แตะพลาดใบสุดท้ายแล้ว
    // เข้าซีนหักเงินทันที ย้อนไม่ได้
    final existing = _picked.indexOf(slotIndex);
    if (existing >= 0) {
      HapticFeedback.selectionClick();
      setState(() {
        _picked.removeAt(existing);
        _reversed.removeAt(existing);
      });
      return;
    }
    if (_picked.length >= _pkg.cards) return;

    HapticFeedback.lightImpact();
    SoundService.instance.cardPick();

    // หัวตั้ง/หัวกลับมาจากกองที่เซิร์ฟเวอร์สับ (50% เท่าเว็บ) ไม่ใช่สุ่มในเครื่อง
    // — ค่าที่ใช้แสดงตอนพลิกต้องเป็นค่าเดียวกับที่จะถูกบันทึกจริง
    final deal = _deal;
    final reversed = deal != null && slotIndex < deal.cards.length
        ? deal.cards[slotIndex].reversed
        : math.Random.secure().nextBool();

    setState(() {
      _picked.add(slotIndex);
      _reversed.add(reversed);
    });
    // ครบจำนวนแล้ว **ไม่** เข้าซีนต่อเอง — รอให้ผู้ใช้กดปุ่มยืนยันที่บอกราคา
    // (ดู _ConfirmBar) เพราะเงินจะถูกตัดหลังจากนั้นโดยย้อนไม่ได้
  }

  /// ไพ่ที่อยู่ในช่อง [slotIndex] — จากกองของเซิร์ฟเวอร์ ถ้าไม่มีใช้สำรับในเครื่อง
  ///
  /// สำรับในเครื่องถูกสับด้วย [_localOrder] ต่อหนึ่งเกม จึงไม่ใช่ลำดับ id เดิม
  TarotCard _cardAt(int slotIndex) {
    final deal = _deal;
    if (deal != null && slotIndex < deal.cards.length) {
      final slug = deal.cards[slotIndex].slug;
      final match = tarotDeck.where((c) => c.slug == slug);
      if (match.isNotEmpty) return match.first;
    }
    return tarotDeck[_localOrder[slotIndex % _localOrder.length]];
  }

  /// ลำดับสับในเครื่อง — สร้างครั้งเดียวต่อหนึ่งเกม (ห้ามสร้างใน build)
  late final List<int> _localOrder =
      List<int>.generate(tarotDeck.length, (i) => i)..shuffle(math.Random.secure());

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
    // กันแตะรัว ๆ ตอนไพ่ใบสุดท้ายพลิกจบ — controller หยุดแล้ว guard ด้านบน
    // เป็น false ทันที สองแตะติดกันจึงเข้ากิ่งเดิมทั้งคู่และยิง POST สองรอบ
    if (_phase != _Phase.reveal) return;
    if (_revealIdx + 1 >= _picked.length) {
      SoundService.instance.complete();
      setState(() => _phase = _Phase.grid);
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      if (!mounted) return;
      await _finalize();
      return;
    }
    setState(() => _revealIdx += 1);
    SoundService.instance.reveal();
    await _revealCtrl.forward(from: 0);
    if (!mounted) return; // controller may complete after pop
  }

  /// บันทึกคำทำนาย: ตัดเงิน → เซิร์ฟเวอร์ตอบทันที (แม่หมออ่านเบื้องหลัง) → ไปหน้าผลซึ่งถามสถานะจนเสร็จ
  /// ทางเดียวที่ออกจาก /shuffle ไป /reading
  Future<void> _finalize() async {
    // Guests must sign in before we can debit a wallet.
    final auth = ref.read(authControllerProvider);
    if (auth is! AuthAuthenticated) {
      _showLoginNeededSheet();
      return;
    }

    setState(() {
      _phase = _Phase.saving;
      _lastError = null;
    });

    try {
      final repo = await ref.read(fortuneRepositoryProvider.future);
      final picks = <TarotPick>[
        for (var i = 0; i < _picked.length; i++)
          TarotPick(
            card: _cardAt(_picked[i]),
            reversed: i < _reversed.length ? _reversed[i] : false,
          ),
      ];
      if (!mounted) return;
      final birth = _pkg.birth && _birthDate != null
          ? DateFormat('yyyy-MM-dd').format(_birthDate!)
          : null;
      final reading = await repo.createTarotReading(
        type: _pkg.type,
        question: _question.trim().isEmpty ? null : _question.trim(),
        picks: picks,
        birthDate: birth,
        // เมื่อมีกองของเซิร์ฟเวอร์ ให้ส่ง "ตำแหน่งที่แตะ" ไปแทน แล้วเซิร์ฟเวอร์
        // แปลงเป็นไพ่+ทิศเอง — ไคลเอนต์จึงเลือกไพ่ที่อยากได้เองไม่ได้
        dealToken: _deal?.token,
        slots: _deal == null ? null : List<int>.from(_picked),
        // ไพ่ชุดเดิม + คำถามเดิม = รายการเดียวกันเสมอ — ส่งซ้ำกี่รอบ (เน็ตหลุด / กด
        // "ลองอีกครั้ง") เซิร์ฟเวอร์ก็คืนรายการเดิม ไม่ตัดเงินซ้ำ
        idempotencyKey: _attempt.begin(
            '${_pkg.type}|${_question.trim()}|${birth ?? ''}|'
            '${picks.map((p) => '${p.card.slug}:${p.reversed}').join(',')}'),
      );
      _attempt.succeeded();

      // ต้องเช็ค mounted ก่อนแตะ ref — ผู้ใช้กด back ระหว่างรอได้
      if (!mounted) return;
      // ยอดเครดิตหน้าแรก/แชท + ประวัติ ต้องสะท้อนการตัดเงินทันที
      // ignore: unawaited_futures
      ref.read(authControllerProvider.notifier).refresh();
      ref.invalidate(fortuneHistoryProvider);

      final id = reading['id'];
      if (id is num) {
        context.pushReplacement('${Routes.reading}?id=${id.toInt()}');
      } else {
        _fail('บันทึกผลไม่สำเร็จ กรุณาลองอีกครั้ง');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      // ยังไม่ถูกตัดเงิน (หรือคืนให้แล้ว) → การกดครั้งหน้าเป็นรายการใหม่ ใช้คีย์ใหม่ได้
      // 409 in_flight เก็บคีย์เดิมไว้ — คำขอแรกอาจยังทำงานอยู่ ลองซ้ำด้วยคีย์เดิมจะได้รายการเดิม
      if (e.reasonCode != 'in_flight' &&
          (e.statusCode == 402 || e.statusCode == 409 || e.statusCode == 422 || e.statusCode == 503)) {
        _attempt.notCharged();
      }
      switch (e.statusCode) {
        case 402:
          _fail(e.message);
          _showInsufficientFundsSheet(e.message);
        case 401:
          _fail('กรุณาเข้าสู่ระบบก่อน แล้วแตะ "ลองอีกครั้ง" — ยังไม่มีการหักเครดิต');
          _showLoginNeededSheet();
        case 409 when e.reasonCode == 'cooldown':
          _fail(e.message, canRetry: false);
          _showCooldownSheet(e.message, (e.body?['reading_id'] as num?)?.toInt());
        case 422 when e.reasonCode == 'deal_expired':
          _fail('กองไพ่หมดอายุแล้ว — กลับไปสับไพ่ใหม่อีกครั้งนะคะ', canRetry: false);
        default:
          _fail(e.message);
      }
    } catch (_) {
      if (!mounted) return;
      _fail('เชื่อมต่อไม่สำเร็จ — ถ้าเครดิตถูกหักไปแล้ว กด "ลองอีกครั้ง" ได้เลย ระบบจะไม่หักซ้ำ');
    }
  }

  /// กลับไปที่ไพ่ที่เปิดแล้วพร้อมเหตุผล + ปุ่มลองอีกครั้ง (ใช้คีย์เดิม ไม่ถูกหักซ้ำ)
  void _fail(String message, {bool canRetry = true}) {
    setState(() {
      _phase = _Phase.grid;
      _lastError = message;
      _canRetry = canRetry;
    });
  }

  bool _canRetry = true;

  Future<void> _showCooldownSheet(String message, int? readingId) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: JuntraColors.bgPurpleDeep,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('ยังเปิดแพ็กเกจนี้ซ้ำไม่ได้',
                  style: baiJamjuree(size: 18, color: JuntraColors.gold)),
              const SizedBox(height: 10),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: JuntraColors.textLavender, height: 1.6)),
              const SizedBox(height: 18),
              if (readingId != null)
                GoldButton(
                  label: 'อ่านคำทำนายเดิม',
                  onPressed: () {
                    Navigator.of(sheetCtx).pop();
                    context.pushReplacement('${Routes.reading}?id=$readingId');
                  },
                ),
              const SizedBox(height: 6),
              GhostButton(
                label: 'เลือกแพ็กเกจอื่น',
                onPressed: () {
                  Navigator.of(sheetCtx).pop();
                  if (context.canPop()) context.pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showInsufficientFundsSheet(String message) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: JuntraColors.bgPurpleDeep,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: JuntraColors.gold.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text('เครดิตไม่พอเปิดไพ่',
                  style: baiJamjuree(size: 18, color: JuntraColors.gold)),
              const SizedBox(height: 8),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13, color: JuntraColors.textLavender, height: 1.5,
                  )),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: JuntraColors.gold,
                    foregroundColor: JuntraColors.bgPurpleDeep,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    Navigator.of(sheetCtx).pop();
                    if (!isPlayChannel) {
                      context.push(Routes.wallet);
                      return;
                    }
                    // แอพ Play: ซื้อเครดิตผ่าน Google Play ในหน้านี้เลย แล้วกดเปิดไพ่ต่อได้ทันที
                    var credited = false;
                    await showPlayCreditsSheet(context, onCredited: () => credited = true);
                    if (credited && mounted) {
                      setState(() {
                        _lastError = 'เติมเครดิตแล้ว — แตะ "ลองอีกครั้ง" เพื่อเปิดไพ่ต่อ';
                        _canRetry = true;
                      });
                    }
                  },
                  child: const Text('เติมเครดิต',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () {
                  Navigator.of(sheetCtx).pop();
                  if (!mounted) return;
                  setState(() => _phase = _Phase.grid);
                },
                child: const Text('ปิด',
                    style: TextStyle(color: JuntraColors.textFaint)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showLoginNeededSheet() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: JuntraColors.bgPurpleDeep,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: JuntraColors.gold.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text('เข้าสู่ระบบก่อนค่ะ',
                  style: baiJamjuree(size: 18, color: JuntraColors.gold)),
              const SizedBox(height: 8),
              const Text(
                'แม่หมอจะบันทึกผลทำนายเก็บไว้ในประวัติของลูก ลูกเข้าสู่ระบบก่อนนะคะ — เครดิตในวอลเลตจะใช้สำหรับเปิดไพ่ครั้งนี้',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13, color: JuntraColors.textLavender, height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: JuntraColors.gold,
                    foregroundColor: JuntraColors.bgPurpleDeep,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.of(sheetCtx).pop();
                    context.push(Routes.login);
                  },
                  child: const Text('เข้าสู่ระบบ',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () {
                  Navigator.of(sheetCtx).pop();
                  if (!mounted) return;
                  setState(() => _phase = _Phase.grid);
                },
                child: const Text('ปิด',
                    style: TextStyle(color: JuntraColors.textFaint)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// เติมวันเกิดจากที่ลูกค้าเคยบันทึกไว้ในหน้าดวงกำเนิด (ไม่ต้องพิมพ์ซ้ำ) — ครั้งเดียว
  void _defaultBirthOnce() {
    if (_birthDefaulted || !_pkg.birth) return;
    _birthDefaulted = true;
    final saved = ref.read(birthDataProvider);
    if (saved.isCustom) {
      _birthDate = DateTime(saved.data.year, saved.data.month, saved.data.day);
    }
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 30, now.month, now.day),
      firstDate: DateTime(1901),
      lastDate: now.subtract(const Duration(days: 1)),
      helpText: 'วันเกิดของลูก (ไม่บังคับ)',
    );
    if (picked != null && mounted) setState(() => _birthDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    // Real web art when available; the built-in drawing is the per-card fallback.
    _catalog = ref.watch(tarotCatalogProvider).valueOrNull ?? TarotCatalog.empty;

    // แพ็กเกจจากเซิร์ฟเวอร์ — ตรึงค่าแรกไว้ทั้งเกม (ดู [_package])
    final pkgAsync = ref.watch(tarotPackageProvider(widget.spreadId));
    _package ??= pkgAsync.valueOrNull;
    if (_package == null) {
      return _PackageGate(loading: pkgAsync.isLoading);
    }
    _defaultBirthOnce();

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
                    _Phase.saving => _buildSavingPhase(),
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
                '${_picked.length}/${_pkg.cards}',
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
          Text(_pkg.nameTh, style: baiJamjuree(size: 16, color: JuntraColors.gold)),
          const SizedBox(height: 8),
          Text('ลูกอยากรู้เรื่องอะไร?', style: baiJamjuree(size: 26)),
          const SizedBox(height: 16),
          const Text(
            'ตั้งใจให้แน่ ก่อนแม่หมอเริ่มสับไพ่ให้ลูก',
            style: TextStyle(fontSize: 13, color: JuntraColors.textMuted),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _questionCtrl,
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
          if (_pkg.birth) ...[
            const SizedBox(height: 14),
            _BirthDateRow(
              date: _birthDate,
              onPick: _pickBirthDate,
              onClear: () => setState(() => _birthDate = null),
            ),
          ],
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
              builder: (_, _) {
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
              Text('เลือกไพ่ ${_pkg.cards} ใบจากสำรับเต็ม 78 ใบ',
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
        // ปุ่มยืนยันที่ **บอกราคาก่อนตัดเงิน** — ของเดิมพอแตะครบจำนวนจะเข้าซีน
        // travel → reveal → หักเงินทันทีโดยไม่เคยบอกว่าจะหักเท่าไร และแตะพลาด
        // ก็ย้อนไม่ได้ (ชนกฎ "Destructive without confirm")
        _ConfirmBar(
          picked: _picked.length,
          needed: _pkg.cards,
          price: _pkg.price?.toDouble(),
          onConfirm: _enterTravel,
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
                  child: CardBackFace(
                    imageUrl: _catalog.cardBackUrl,
                    width: 90, height: 145,
                  ),
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
    final card = _cardAt(_picked[_revealIdx]);
    final positionLabel = _revealIdx < _pkg.positions.length
        ? _pkg.positions[_revealIdx] : '';
    // ทิศของไพ่มาจากกองที่เซิร์ฟเวอร์สับ และเป็นค่าเดียวกับที่ถูกบันทึก/แม่หมอตีความ
    // — ต้องพลิกให้เห็นกลับหัวตั้งแต่ตอนนี้ ไม่ใช่เห็นหัวตั้งแล้วไปกลับหัวในหน้าผล
    final reversed = _revealIdx < _reversed.length && _reversed[_revealIdx];

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
                  builder: (_, _) {
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
                            ? Transform.rotate(
                                angle: reversed ? math.pi : 0,
                                child: CardFace(
                                  card: card,
                                  imageUrl: _catalog.faceUrlFor(card.slug),
                                  width: 180, height: 290,
                                ),
                              )
                            : Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.rotationY(math.pi),
                                child: CardBackFace(
                                  imageUrl: _catalog.cardBackUrl,
                                  width: 180, height: 290,
                                ),
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
            child: Text(_catalog.nameThFor(card.slug) ?? card.thai,
                style: baiJamjuree(size: 28, color: Colors.white)),
          ),
          const SizedBox(height: 4),
          Text('ใบที่ ${_revealIdx + 1} · $positionLabel${reversed ? ' (กลับหัว)' : ''}',
              style: const TextStyle(
                fontSize: 12, color: JuntraColors.textMuted,
              )),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: GhostButton(
              label: _revealIdx + 1 == _picked.length
                  ? 'ดูคำทำนายเต็ม →' : 'ใบถัดไป →',
              onPressed: _nextReveal,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Phase 6: Grid (brief landing then route) ──────────────
  Widget _buildGridPhase() {
    final cards = Wrap(
        spacing: 8, runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (var k = 0; k < _picked.length; k++)
            Transform.rotate(
              angle: k < _reversed.length && _reversed[k] ? math.pi : 0,
              child: CardFace(
                card: _cardAt(_picked[k]),
                imageUrl: _catalog.faceUrlFor(_cardAt(_picked[k]).slug),
                nameTh: _catalog.nameThFor(_cardAt(_picked[k]).slug),
                width: 72, height: 118,
              ),
            ),
        ],
      );
    if (_lastError == null) {
      return Center(key: const ValueKey('g'), child: cards);
    }
    return Center(
      key: const ValueKey('g-err'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 70, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            cards,
            const SizedBox(height: 22),
            Text(_lastError!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: JuntraColors.textLavender, height: 1.6)),
            const SizedBox(height: 16),
            if (_canRetry)
              GoldButton(
                label: 'ลองอีกครั้ง',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _finalize,
              ),
            const SizedBox(height: 6),
            GhostButton(
              label: 'กลับไปเลือกแพ็กเกจ',
              onPressed: () => context.canPop() ? context.pop() : context.go(Routes.home),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Phase 7: Saving (POST /v1/history/readings, AI interpret) ──
  // Spinner + reassuring copy while juntraweb debits the wallet, calls
  // FortuneAiService (Thaiprompt pool with local AiOracle fallback), and
  // persists the Reading row. Worst-case path: 8-12s with cold AI key.
  Widget _buildSavingPhase() {
    return Center(
      key: const ValueKey('save'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 64, height: 64,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: const AlwaysStoppedAnimation<Color>(JuntraColors.gold),
                backgroundColor: JuntraColors.gold.withValues(alpha: 0.2),
              ),
            ),
            const SizedBox(height: 28),
            Text('แม่หมอกำลังพิจารณาไพ่ของลูก...',
                style: baiJamjuree(size: 16, color: JuntraColors.gold)),
            const SizedBox(height: 8),
            const Text(
              'รอสักครู่นะคะ · กำลังบันทึกผลทำนายและเตรียมคำอธิบาย',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12, color: JuntraColors.textMuted, height: 1.5,
              ),
            ),
          ],
        ),
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
      builder: (_, _) => Transform.rotate(
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

/// แถบยืนยันก่อนเปิดไพ่ — บอกจำนวนที่เลือกและราคาที่จะถูกหัก
class _ConfirmBar extends StatelessWidget {
  const _ConfirmBar({
    required this.picked,
    required this.needed,
    required this.onConfirm,
    this.price,
  });

  final int picked;
  final int needed;
  final double? price;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final ready = picked >= needed;
    final priceText = price == null
        ? ''
        : (price == 0 ? ' · ฟรี' : ' · ${formatCredits(price!.round())}');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            ready
                ? 'เลือกครบแล้ว · แตะไพ่ที่เลือกอีกครั้งเพื่อเปลี่ยนใจได้'
                : 'เลือกแล้ว $picked / $needed ใบ',
            style: const TextStyle(fontSize: 11.5, color: JuntraColors.textMuted),
          ),
          const SizedBox(height: 8),
          GoldButton(
            label: ready ? 'เปิดไพ่$priceText' : 'เลือกให้ครบ $needed ใบ',
            size: GoldButtonSize.lg,
            disabled: !ready,
            onPressed: onConfirm,
          ),
        ],
      ),
    );
  }
}

/// รอแพ็กเกจจากเซิร์ฟเวอร์ / แพ็กเกจปิดขายไปแล้ว
class _PackageGate extends StatelessWidget {
  const _PackageGate({required this.loading});
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const StarryBackground(density: 50, intensity: 0.7),
          SafeArea(
            child: Center(
              child: loading
                  ? const CircularProgressIndicator(color: JuntraColors.gold)
                  : Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.style_outlined, color: JuntraColors.textFaint, size: 44),
                          const SizedBox(height: 12),
                          Text('แพ็กเกจนี้ปิดขายชั่วคราว', style: baiJamjuree(size: 18, color: JuntraColors.gold)),
                          const SizedBox(height: 8),
                          const Text('เลือกแพ็กเกจอื่นได้เลยนะคะ — ยังไม่มีการหักเครดิต',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: JuntraColors.textMuted)),
                          const SizedBox(height: 18),
                          GhostButton(
                            label: 'ดูแพ็กเกจทั้งหมด',
                            onPressed: () => context.go(Routes.spreads),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// วันเกิดแบบไม่บังคับ — แม่หมอผสานดวงวันเกิดเข้ากับไพ่ (Celtic · 12 เดือน · คุณไสย)
class _BirthDateRow extends StatelessWidget {
  const _BirthDateRow({required this.date, required this.onPick, required this.onClear});
  final DateTime? date;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final d = date;
    final label = d == null
        ? 'ใส่วันเกิด (ไม่บังคับ) — แม่หมอผสานดวงเกิดให้แม่นขึ้น'
        : 'วันเกิด: ${d.day} ${DateFormat('MMMM', 'th').format(d)} ${d.year + 543}';
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: JuntraColors.purple.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.cake_outlined, color: JuntraColors.gold, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 13, color: JuntraColors.textLavender)),
            ),
            if (d != null)
              IconButton(
                icon: const Icon(Icons.close_rounded, color: JuntraColors.textFaint, size: 18),
                onPressed: onClear,
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }
}
