import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/chat_repository.dart';
import '../../core/api/app_config_repository.dart';
import '../../core/api/rooms_repository.dart';
import '../../core/api/tarot_packages_repository.dart';
import '../../shared/format/credits.dart';
import '../../shared/widgets/gold_button.dart';
import '../../shared/widgets/juntra_tab_bar.dart';
import '../../shared/widgets/starry_background.dart';
import 'room_packages.dart';
import 'room_visuals.dart';

/// หน้า "เลือก ผู้พยากรณ์" — เว็บ `/chat` ที่ยังไม่เลือกห้อง (pages/chat/rooms.blade.php)
///
/// การ์ดละหนึ่งห้อง (บุษบา · แม่หมอ · คุณไสย) ข้อมูลจาก `GET /v1/chat/rooms` ทั้งหมด
/// ห้องที่ยังไม่เปิดโชว์ "เร็ว ๆ นี้" กดไม่ได้ · กำลังทำนายอยู่ห้องหนึ่ง (meta.lock) เข้าห้องอื่นไม่ได้
///
/// เซิร์ฟเวอร์เก่า/เปิดห้องเดียว (`hasPicker == false`) ไม่มีอะไรให้เลือก → เข้าห้องแม่หมอเลย
/// เหมือนเว็บ (และเหมือนแอพ 0.6.0 ที่แท็บ "แม่หมอ" เปิดแชทตรง ๆ)
class RoomsScreen extends ConsumerStatefulWidget {
  const RoomsScreen({super.key});

  @override
  ConsumerState<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends ConsumerState<RoomsScreen>
    with WidgetsBindingObserver {
  bool _redirected = false;

  // ตัวเลขสด — ถามใหม่ตาม refresh_seconds เฉพาะตอนที่หน้านี้อยู่บนจอจริง
  Timer? _liveTimer;
  bool _foreground = true;
  bool _onTop = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // TickerMode ปิดเมื่อมีหน้าทึบมาทับ (เข้าห้องแชท/สับไพ่) — หยุดถามตัวเลขสดตอนนั้น
    final onTop = TickerMode.valuesOf(context).enabled;
    if (onTop != _onTop) {
      _onTop = onTop;
      _onVisibilityChanged();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg == _foreground) return;
    _foreground = fg;
    _onVisibilityChanged();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _liveTimer?.cancel();
    super.dispose();
  }

  bool get _visible => _foreground && _onTop;

  void _onVisibilityChanged() {
    _liveTimer?.cancel();
    _liveTimer = null;
    // กลับมาเห็นหน้าอีกครั้ง = ถามเลขใหม่ทันที (เลขเดิมอาจเก่าไปหลายนาที)
    if (_visible && mounted) ref.invalidate(chatLiveStatsProvider);
  }

  /// เน็ตสะดุด — คงเลขเดิมไว้แล้วถามใหม่ห่าง ๆ (ไม่ใช่เลิกถามทั้งรอบ)
  static const _liveRetry = Duration(seconds: 30);

  void _onLive(AsyncValue<ChatLiveStats?> next) {
    if (next.isLoading) return;
    if (next.hasError) {
      _scheduleLive(_liveRetry);
      return;
    }
    final stats = next.valueOrNull;
    // null = เซิร์ฟเวอร์ไม่มีบริการนี้ (404) — ซ่อนป้ายและเลิกถาม จนกว่าจะกลับเข้าหน้านี้ใหม่
    _scheduleLive(
      stats == null ? null : Duration(seconds: stats.refreshSeconds),
    );
  }

  void _scheduleLive(Duration? after) {
    _liveTimer?.cancel();
    _liveTimer = null;
    if (after == null || !_visible) return;
    _liveTimer = Timer(after, () {
      if (mounted && _visible) ref.invalidate(chatLiveStatsProvider);
    });
  }

  void _redirectIfNoPicker(RoomsState state) {
    if (_redirected || state.hasPicker) return;
    _redirected = true;
    final open = state.openRooms;
    final key = open.isEmpty ? OracleRoom.defaultKey : open.first.key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('${Routes.chat}?room=$key');
    });
  }

  void _enter(RoomsState state, OracleRoom room) {
    if (!room.open) return;
    final lock = state.lock;
    if (lock != null &&
        lock.active &&
        lock.room != room.key &&
        state.room(lock.room).open) {
      _showLock(state, lock);
      return;
    }
    context.go('${Routes.chat}?room=${room.key}');
  }

  void _showLock(RoomsState state, RoomLock lock) {
    final target = state.room(lock.room);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          lock.message ??
              'กำลังทำนายอยู่ในห้อง${target.short} — กลับไปคุยต่อให้จบก่อนนะคะ',
        ),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'ไปห้อง${target.short}',
          onPressed: () {
            if (mounted) context.go('${Routes.chat}?room=${target.key}');
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    final enabled = config.valueOrNull?.has('rooms') ?? false;
    final async = enabled
        ? ref.watch(roomsProvider)
        : config.isLoading
        ? const AsyncLoading<RoomsState>()
        : AsyncData(RoomsState.legacy);
    // roomsProvider ตกไปห้องสำรองเองแทบทุกกรณี — error จริง (เช่นสร้าง ApiClient ไม่ได้) ก็ถือเป็นห้องเดียว
    final state =
        async.valueOrNull ?? (async.hasError ? RoomsState.legacy : null);
    if (state != null) _redirectIfNoPicker(state);

    // ตัวเลขสดถามเฉพาะตอนมีหน้าเลือกห้องจริง (เซิร์ฟเวอร์เก่าไม่มี /chat/live — ไม่ยิงให้เสีย 404)
    final picker = state != null && state.hasPicker;
    ChatLiveStats? live;
    if (picker) {
      ref.listen<AsyncValue<ChatLiveStats?>>(
        chatLiveStatsProvider,
        (_, next) => _onLive(next),
      );
      live = ref.watch(chatLiveStatsProvider).valueOrNull;
    }

    return Scaffold(
      bottomNavigationBar: const JuntraTabBar(currentIndex: 2),
      body: Stack(
        children: [
          const StarryBackground(),
          SafeArea(
            bottom: false,
            // โหลดครั้งแรกเท่านั้นที่เห็นวงหมุน · ดึงลงรีเฟรชแล้วการ์ดเดิมยังอยู่
            child: !picker
                ? const Center(
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: JuntraColors.gold,
                      ),
                    ),
                  )
                : RefreshIndicator(
                    color: JuntraColors.gold,
                    backgroundColor: JuntraColors.bgPurpleDeep,
                    onRefresh: () async {
                      ref.invalidate(chatLiveStatsProvider);
                      ref.invalidate(tarotPackagesProvider);
                      ref.invalidate(roomsProvider);
                      try {
                        await ref.read(roomsProvider.future);
                      } catch (_) {
                        /* roomsProvider ตกไปห้องสำรองเอง */
                      }
                    },
                    child: _content(state, live),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _content(RoomsState state, ChatLiveStats? live) {
    final packages =
        ref.watch(tarotPackagesProvider).valueOrNull ?? const <TarotPackage>[];
    final lock = state.lock;
    final lockActive =
        lock != null && lock.active && state.room(lock.room).open;
    final chatFree = state.freeDaily || (state.chatCost ?? 1) <= 0;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        Padding(
          padding: const EdgeInsets.only(
            right: StarryBackground.logoReserve - 16,
          ),
          child: Row(
            children: [
              if (context.canPop())
                IconButton(
                  icon: const Icon(
                    Icons.chevron_left,
                    color: JuntraColors.gold,
                    size: 28,
                  ),
                  tooltip: 'ย้อนกลับ',
                  onPressed: () => context.pop(),
                ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.history, color: JuntraColors.textMuted),
                tooltip: 'บทสนทนาเก่า',
                onPressed: () => context.pushOnce(Routes.chatConversations),
              ),
            ],
          ),
        ),
        _Hero(lede: _lede(state), disclosure: state.aiDisclosure),
        if (live != null) ...[
          const SizedBox(height: 14),
          Center(child: _LiveChip(stats: live)),
        ],
        if (lockActive) ...[
          const SizedBox(height: 14),
          _LockBanner(
            lock: lock,
            room: state.room(lock.room),
            onGo: () => context.go('${Routes.chat}?room=${lock.room}'),
          ),
        ],
        const SizedBox(height: 18),
        for (var i = 0; i < state.rooms.length; i++)
          _RoomCard(
                room: state.rooms[i],
                index: i,
                total: state.rooms.length,
                packages: roomPackages(state.rooms[i], packages),
                chatFree: chatFree,
                current: lockActive && lock.room == state.rooms[i].key,
                onEnter: () => _enter(state, state.rooms[i]),
              )
              .animate()
              .fadeIn(duration: 380.ms, delay: (80 * i).ms)
              .slideY(begin: 0.06),
      ],
    );
  }

  /// meta.lede ของเซิร์ฟเวอร์ — ไม่มีก็ประกอบจากราคา/โควตาแบบเดียวกับ ChatPolicy::lede ของเว็บ
  String _lede(RoomsState s) {
    final lede = s.lede?.trim();
    if (lede != null && lede.isNotEmpty) return lede;
    final cost = s.chatCost ?? 0;
    final limit = s.dailyLimit ?? 0;
    final head = cost <= 0 && limit <= 0
        ? 'คุยฟรีทุกวัน'
        : limit > 0
        ? 'คุยฟรีวันละ $limit ข้อความ'
        : 'คุยข้อความละ ${formatCredits(cost)}';
    return '$head · อยากให้เปิดไพ่เมื่อไรค่อยเลือก ราคาไพ่หักตอนเปิดไพ่เท่านั้น';
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.lede, this.disclosure});

  final String lede;
  final String? disclosure;

  static const _defaultDisclosure =
      'ผู้พยากรณ์ทุกห้องคือ หมอดู AI เปิดไพ่แล้วอ่านจากความหมายในตำราไพ่ 78 ใบ ตามใบและตำแหน่งที่ท่านเปิดได้จริง — ไม่เดา ไม่มโน';

  @override
  Widget build(BuildContext context) {
    final text = (disclosure?.trim().isNotEmpty ?? false)
        ? disclosure!.trim()
        : _defaultDisclosure;
    return Column(
      children: [
        Text(
          'CHOOSE YOUR ORACLE',
          style: cinzel(size: 11, color: JuntraColors.goldMid),
        ),
        const SizedBox(height: 6),
        ShaderMask(
          shaderCallback: (r) => JuntraColors.headlineGradient.createShader(r),
          blendMode: BlendMode.srcIn,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'เลือก ',
                  style: charm(size: 34, color: Colors.white),
                ),
                TextSpan(
                  text: 'ผู้พยากรณ์',
                  style: charm(size: 38, color: Colors.white),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          lede,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13.5,
            color: JuntraColors.textLavender,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: JuntraColors.bgDeepest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(JuntraRadius.input),
            border: Border.all(color: JuntraColors.lineSoft),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(padding: EdgeInsets.only(top: 1), child: AiBadge()),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: JuntraColors.textLavender,
                    height: 1.55,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LiveChip extends StatelessWidget {
  const _LiveChip({required this.stats});
  final ChatLiveStats stats;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      'ออนไลน์ ${stats.online}',
      if (stats.chatting > 0) 'กำลังคุย ${stats.chatting}',
      if (stats.queue > 0) 'คิวเปิดไพ่ ${stats.queue}',
    ];
    return Semantics(
      liveRegion: false,
      label: parts.join(' · '),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: JuntraColors.mintGreen.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(JuntraRadius.chip),
          border: Border.all(
            color: JuntraColors.mintGreen.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const OnlineDot(),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                parts.join(' · '),
                style: const TextStyle(
                  fontSize: 12,
                  color: JuntraColors.textLavender,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LockBanner extends StatelessWidget {
  const _LockBanner({
    required this.lock,
    required this.room,
    required this.onGo,
  });

  final RoomLock lock;
  final OracleRoom room;
  final VoidCallback onGo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: room.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(JuntraRadius.input),
        border: Border.all(color: room.accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_clock_outlined, color: room.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              lock.message ??
                  'กำลังทำนายอยู่ในห้อง${room.short} — กลับไปคุยต่อให้จบก่อนนะคะ',
              style: const TextStyle(
                fontSize: 12.5,
                color: JuntraColors.textLavender,
                height: 1.5,
              ),
            ),
          ),
          TextButton(onPressed: onGo, child: Text('ไปห้อง${room.short}')),
        ],
      ),
    );
  }
}

/// การ์ดห้อง (เว็บ `.room-card`)
class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.index,
    required this.total,
    required this.packages,
    required this.chatFree,
    required this.current,
    required this.onEnter,
  });

  final OracleRoom room;
  final int index;
  final int total;
  final List<TarotPackage> packages;
  final bool chatFree;

  /// ห้องที่ล็อกไว้ระหว่างทำนาย — ไฮไลต์ให้เห็นว่ากลับไปห้องนี้
  final bool current;
  final VoidCallback onEnter;

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final accent = room.accent;
    final open = room.open;
    final product = room.product;

    return Opacity(
      opacity: open ? 1 : 0.62,
      child: Container(
        margin: const EdgeInsets.only(bottom: 18),
        decoration: BoxDecoration(
          gradient: JuntraColors.purpleCardGradient,
          borderRadius: BorderRadius.circular(JuntraRadius.hero),
          border: Border.all(
            color: accent.withValues(
              alpha: current ? 0.95 : (open ? 0.55 : 0.25),
            ),
            width: current ? 1.6 : 1,
          ),
          boxShadow: [
            if (open)
              BoxShadow(
                color: accent.withValues(alpha: 0.28),
                blurRadius: 26,
                spreadRadius: -8,
                offset: const Offset(0, 10),
              ),
            ...JuntraShadows.cardDeep,
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(JuntraRadius.hero),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: open ? onEnter : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                    aspectRatio: 4 / 3.4,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        RoomImage(
                          roomKey: room.key,
                          imageUrl: room.imageUrl ?? room.media.stillUrl,
                        ),
                        // ภาพจางลงพื้นการ์ด ให้ชื่อห้องอ่านออกบนรูป
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0x000A0612),
                                Color(0x330A0612),
                                Color(0xF20A0612),
                              ],
                              stops: [0.35, 0.6, 1],
                            ),
                          ),
                        ),
                        Positioned(
                          left: 12,
                          top: 12,
                          right: 12,
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _Badge(
                                text: '${_two(index + 1)} / ${_two(total)}',
                              ),
                              const AiBadge(large: true),
                              if (open)
                                const _Badge(text: 'ออนไลน์', online: true)
                              else
                                const _Badge(text: 'เร็ว ๆ นี้'),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 12,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                room.eyebrow,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: accent,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                room.name,
                                style: charm(
                                  size: 28,
                                  color: JuntraColors.moon,
                                ),
                              ),
                              Text(
                                room.title,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: JuntraColors.textLavender,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '“${room.quote}”',
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontStyle: FontStyle.italic,
                            color: JuntraColors.textCream,
                            height: 1.6,
                          ),
                        ),
                        if (room.tags.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final t in room.tags)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accent.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(
                                      JuntraRadius.chip,
                                    ),
                                    border: Border.all(
                                      color: accent.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  child: Text(
                                    t,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: JuntraColors.textLavender,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        if (open && packages.isNotEmpty)
                          for (final p in packages)
                            RoomPackageRow(package: p, accent: accent)
                        else if (product != null && product.name.isNotEmpty)
                          // ห้องยังปิด / ไม่รู้แพ็กเกจ — บอกแพ็กเกจประจำห้องใบเดียวแบบเว็บ
                          _ProductRow(product: product, accent: accent),
                        const SizedBox(height: 6),
                        if (open)
                          GoldButton(
                            label: current
                                ? 'กลับเข้าห้อง${room.short}'
                                : 'เข้าห้อง${room.short}${chatFree ? ' · คุยฟรี' : ''}',
                            full: true,
                            icon: const Icon(Icons.arrow_forward, size: 18),
                            onPressed: onEnter,
                          )
                        else
                          const GhostButton(
                            label: 'เร็ว ๆ นี้',
                            full: true,
                            onPressed: null,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.accent});
  final RoomProduct product;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final price = product.price;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: JuntraColors.bgDeepest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(JuntraRadius.input),
        border: Border.all(color: JuntraColors.lineSoft),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.14),
              border: Border.all(color: accent.withValues(alpha: 0.55)),
            ),
            child: Text(
              product.cards > 0 ? '${product.cards}' : '★',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: JuntraColors.textCream,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              product.name,
              style: const TextStyle(
                fontSize: 13,
                color: JuntraColors.textLavender,
              ),
            ),
          ),
          if (price != null)
            Text(
              price <= 0 ? 'ฟรี' : formatCredits(price),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: JuntraColors.gold,
              ),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, this.online = false});
  final String text;
  final bool online;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: JuntraColors.bgDeepest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(JuntraRadius.chip),
        border: Border.all(
          color: online
              ? JuntraColors.mintGreen.withValues(alpha: 0.5)
              : JuntraColors.line,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (online) ...[const OnlineDot(size: 6), const SizedBox(width: 5)],
          Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              height: 1.1,
              color: JuntraColors.textCream,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
