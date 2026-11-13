import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/app_config_repository.dart';
import '../../core/api/chat_repository.dart';
import '../../core/api/report_repository.dart';
import '../../core/api/rooms_repository.dart';
import '../../core/app_channel.dart';
import '../../core/auth/auth_state.dart';
import '../../core/auth/session.dart';
import '../../core/voice/speech_input.dart';
import '../../core/voice/voice_clip_player.dart';
import '../../shared/format/credits.dart';
import '../../shared/widgets/gold_button.dart';
import '../../shared/widgets/juntra_tab_bar.dart';
import '../../shared/widgets/report_content_sheet.dart';
import '../../shared/widgets/starry_background.dart';
import '../wallet/play_credits_panel.dart';
import 'chat_clock.dart';
import 'chat_topics_sheet.dart';
import 'chat_topup_sheet.dart';
import 'room_packages.dart';
import 'room_stage.dart';
import 'room_visuals.dart';

/// Screen 7 — ห้องผู้พยากรณ์ (บุษบา · แม่หมอ · คุณไสย) — เว็บ จันทรา.online/chat?room=
///
/// Wired to `POST /v1/chat/conversations` (start) and `/v1/chat/conversations/{id}/send`,
/// which proxy to the Thaiprompt prediction lane server-side (แอพไม่ถือคีย์ AI).
///
/// ความสอดคล้องกับเว็บ — ต้องเท่ากันทุกอย่าง:
///   - ห้อง/ชื่อ/ภาพ/คำทักของผู้พยากรณ์มาจากห้องของบทสนทนา (`persona`/`room`) ไม่ใช่แม่หมอตายตัว
///   - ปุ่มคำถามลัด (`suggestions` จาก ChatSuggestions) + ปุ่มที่ผู้พยากรณ์คิดให้ (`ai_suggestions`)
///   - ยุบแถบปุ่มเมื่อผู้พยากรณ์กำลังถามกลับ (`awaiting`) ไม่ให้บทสนทนาหลุดโฟลว์ทำนาย
///   - นาฬิกาถามต่อหลังเปิดไพ่ (`qa`) / ถามฟรีหลังไพ่ฟรี (`free_ask`) ตามเวลาเซิร์ฟเวอร์ + ปุ่ม "พอแล้ว"
///   - ทีมงานคุมห้อง (`held`) → ไม่มีฟองคำตอบจากบอท รอข้อความของเจ้าหน้าที่ทาง `…/feed`
///   - บิลค้างของห้อง (`pending_bill`) — ช่อง APK เท่านั้น
///   - แยกเคส 402 / 429 daily_limit / 429 rate-limit / 409 (in_flight · busy_other · qa_over) / 422 / 423
///   - เรียกลูกค้าว่า "คุณ" ทุกห้อง (เลิกใช้ "ลูก" ตั้งแต่ 2026-11-10)
///
/// เซิร์ฟเวอร์เก่า (ยังไม่มีระบบห้อง): ไม่ส่ง `room` ตอนเปิดห้อง (ไม่งั้นได้ห้องเปล่างอกทุกครั้ง)
/// เปิดบทสนทนาล่าสุดต่อเหมือนเดิม · ไม่มีนาฬิกา/บิล/feed/เสียง — เหมือนแอพ 0.6.0 ทุกอย่าง
///
/// Entry modes:
///   - `/chat?reading=N`        → คุยต่อจากคำทำนายใบนั้น
///   - `/chat?id=N`             → resume บทสนทนาที่ระบุ
///   - `/chat?room=K[&new=1]`   → ห้องคุยทั่วไปของผู้พยากรณ์คนนั้น (คุยต่อห้องล่าสุด / ห้องใหม่)
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    this.resumeConversationId,
    this.fromReadingId,
    this.room,
    this.startNew = false,
  });

  /// If provided, load that conversation instead of the most recent one.
  final int? resumeConversationId;

  /// เปิดห้องคุยต่อจากคำทำนายไพ่ใบนี้ ("คุยต่อ" ในหน้าผล)
  final int? fromReadingId;

  /// ห้องผู้พยากรณ์ (busaba · maemor · kunsai) — null = ห้องแม่หมอ / ห้องของคำทำนาย
  final String? room;

  /// true = เริ่มบทสนทนาใหม่ในห้องนี้ ไม่คุยต่อห้องเดิม
  final bool startNew;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen>
    with WidgetsBindingObserver {
  static const _kSoundPref = 'juntra_room_sound_v1';

  /// ถามหาข้อความเจ้าหน้าที่ทุก 4 วิ นานสุด 3 นาทีต่อรอบ (ลูกค้าส่งใหม่ = เริ่มนับใหม่)
  static const _feedEvery = Duration(seconds: 4);
  static const _feedFor = Duration(minutes: 3);

  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_Msg>[];

  bool _typing = false;
  bool _starting = true;
  int? _conversationId;

  /// เซิร์ฟเวอร์มีระบบห้อง (`features.rooms`) — ไม่มี = ห้ามส่ง `room` ตอนเปิดห้อง
  bool _hasRooms = false;

  // ห้องของบทสนทนานี้ — ก่อนเปิดห้องเสร็จใช้ห้องจาก URL
  late String _roomKey = OracleRoom.normalize(widget.room);
  ChatRoomBrief? _brief;

  /// เข้าห้องไม่ได้ (ห้องถูกล็อกระหว่างทำนายอยู่อีกห้อง) — โชว์แผงพาไปห้องนั้นแทนแชท
  _LockGate? _gate;

  // สถานะโควตา/ปุ่มลัด — ซิงก์จากทุก response ของ backend ไม่เดาเอง
  List<ChatSuggestion> _suggestions = const [];
  List<String> _aiSuggestions = const [];
  bool _awaiting = false; // ผู้พยากรณ์กำลังรอคำตอบอยู่
  bool _suggestOpen = false; // ผู้ใช้กดกางปุ่มลัดตอน awaiting
  bool _blocked = false; // คุยต่อไม่ได้ (ครบโควตา / เครดิตหมด)
  String _blockedReason = '';
  int _dailyLimit = 0;
  int _dailyLeft = 0;
  double _cost = 0;

  // นาฬิกาถามต่อ / ถามฟรี · บิลค้าง (เวลาทั้งหมดของเซิร์ฟเวอร์)
  ChatClock? _qa;
  ChatClock? _freeAsk;
  bool _qaExpiredHere = false; // นับถึงศูนย์บนเครื่องแล้ว (ก่อนเซิร์ฟเวอร์บอก)
  String? _qaOverMessage; // ข้อความ "หมดเวลาถามต่อ" ของเซิร์ฟเวอร์
  bool _qaEnding = false;
  bool _roomGone = false; // 422 room_closed — กำลังพากลับหน้าเลือกห้อง
  bool _newChatConfirming = false;
  bool _paymentOpen = false;
  ChatPendingBill? _bill;

  // ทีมงานคุมห้อง — ถามหาข้อความใหม่ทาง feed
  bool _held = false;
  Timer? _feedTimer;
  DateTime? _feedUntil;
  bool _feedBusy = false;

  // เสียง · ไมค์
  late final VoiceClipPlayer _voice = VoiceClipPlayer();
  final SpeechInput _speech = SpeechInput();
  bool _micHidden = !SpeechInput.platformSupported;
  bool _listening = false;
  bool _micStarting = false;
  String _micBase = '';
  bool _soundOn = false; // เว็บตั้งต้นปิดเสียง
  bool _greeted = false;

  bool _foreground = true;
  bool _onTop = true;

  /// เพิ่มทุกครั้งที่เริ่มห้องใหม่ — คำตอบของรอบเก่าที่มาช้าห้ามเขียนทับห้องใหม่
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bootstrap();
    });
  }

  @override
  void didUpdateWidget(ChatScreen old) {
    super.didUpdateWidget(old);
    // go_router อาจใช้ State เดิมเมื่อไปที่ /chat ด้วยพารามิเตอร์ใหม่ (เช่นปุ่มไปห้องที่ล็อกไว้)
    if (old.room != widget.room ||
        old.startNew != widget.startNew ||
        old.resumeConversationId != widget.resumeConversationId ||
        old.fromReadingId != widget.fromReadingId) {
      _resetRoom(OracleRoom.normalize(widget.room));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _bootstrap();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // มีหน้าทึบมาทับ (สับไพ่/รายการบทสนทนา) → หยุดเสียง ไมค์ และการถาม feed
    final onTop = TickerMode.valuesOf(context).enabled;
    if (onTop == _onTop) return;
    _onTop = onTop;
    _onVisibilityChanged();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg == _foreground) return;
    _foreground = fg;
    _onVisibilityChanged();
  }

  void _onVisibilityChanged() {
    if (_foreground && _onTop) {
      if (_feedUntil != null) _scheduleFeed();
    } else {
      _feedTimer?.cancel();
      _feedTimer = null;
      unawaited(_voice.stop());
      unawaited(_speech.stop());
      if (mounted) {
        setState(() {
          _listening = false;
          _micStarting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _feedTimer?.cancel();
    _speech.dispose();
    unawaited(_voice.dispose());
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /* ══════════════════════ ห้อง ══════════════════════ */

  OracleRoom get _room =>
      (_hasRooms ? ref.read(roomsValueProvider) : RoomsState.legacy).room(
        _roomKey,
      );

  /// คำเรียกตัวเองของผู้พยากรณ์ (บุษบา / แม่หมอ) — ข้อความที่แอพประกอบเองต้องใช้ตามห้อง
  String get _self => _brief?.short ?? _room.short;

  bool get _qaOver => _qaExpiredHere || (_qa?.isOver() ?? false);

  /// เสียงคำตอบพรีเมียม (`reply_voice`) — เฉพาะเซิร์ฟเวอร์ที่ประกาศ `features.voice_premium`
  bool get _voiceOk => ref.read(appConfigValueProvider).has('voice_premium');

  String get _qaOverText =>
      _qaOverMessage ??
      'หมดเวลาถามต่อของไพ่ชุดนี้แล้วนะคะ ขอบคุณที่ให้$_selfได้อ่านไพ่ให้ค่ะ 🌙 '
          'อยากคุยเรื่องอื่นต่อ หรือเปิดไพ่ชุดใหม่ กดปุ่มด้านล่างได้เลยค่ะ';

  String get _dailyDoneReason =>
      'วันนี้คุยครบแล้ว — พรุ่งนี้$_selfรอฟังต่อนะคะ';

  /// ล้างทุกอย่างของห้องเดิม (เปิดห้องใหม่ / สลับผู้ใช้ / เปลี่ยนห้อง)
  void _resetRoom(String roomKey) {
    _epoch++;
    _stopFeed();
    unawaited(_voice.stop());
    unawaited(_speech.stop());
    setState(() {
      _roomKey = roomKey;
      _brief = null;
      _gate = null;
      _starting = true;
      _typing = false;
      _conversationId = null;
      _messages.clear();
      _suggestions = const [];
      _aiSuggestions = const [];
      _awaiting = false;
      _suggestOpen = false;
      _blocked = false;
      _blockedReason = '';
      _qa = null;
      _freeAsk = null;
      _qaExpiredHere = false;
      _qaOverMessage = null;
      _qaEnding = false;
      _roomGone = false;
      _bill = null;
      _held = false;
      _greeted = false;
      _listening = false;
      _micStarting = false;
      _dailyLimit = 0;
      _dailyLeft = 0;
      _cost = 0;
    });
  }

  /* ══════════════════════ session ══════════════════════ */

  Future<void> _bootstrap() async {
    final epoch = _epoch;
    final auth = ref.read(authControllerProvider);

    // AuthUnknown = ยังโหลด session ไม่เสร็จ ต้องรอ ไม่ใช่ปล่อยผ่านไปยิง API
    // แล้วไปเจอ 401 (ของเดิมเช็คเฉพาะ AuthGuest ผู้ใช้ที่เพิ่งเปิดแอพจึงเห็น
    // "session หมดอายุ" ทั้งที่ล็อกอินอยู่)
    if (auth is AuthUnknown || auth is AuthOffline) {
      await ref.read(authControllerProvider.notifier).refresh();
    }

    if (!mounted || epoch != _epoch) return;
    if (ref.read(authControllerProvider) is! AuthAuthenticated) {
      setState(() => _starting = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(Routes.login);
      });
      return;
    }

    final cfg = await _config();
    if (!mounted || epoch != _epoch) return;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || epoch != _epoch) return;
    _hasRooms = cfg.has('rooms');
    if (!_hasRooms) _roomKey = OracleRoom.defaultKey;
    _soundOn = prefs.getBool(_kSoundPref) ?? false;

    final readingId = widget.fromReadingId;
    if (readingId != null) {
      await _startSession(readingId: readingId);
      return;
    }
    final resumeId = widget.resumeConversationId;
    if (resumeId != null) {
      await _resumeSession(resumeId);
    } else if (_hasRooms) {
      // เซิร์ฟเวอร์คุยต่อห้องล่าสุดของผู้พยากรณ์คนนี้ให้เอง (เว้นแต่ขอห้องใหม่)
      await _startSession(room: _roomKey, startNew: widget.startNew);
    } else if (widget.startNew) {
      await _startSession();
    } else {
      await _openLatestOrStart();
    }
  }

  /// สวิตช์ฟีเจอร์ของเซิร์ฟเวอร์ — ปกติโหลดไว้ตั้งแต่เปิดแอพแล้ว รอไม่เกิน 6 วิ
  Future<AppConfig> _config() async {
    try {
      return await ref
          .read(appConfigProvider.future)
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      if (!mounted) return AppConfig.fallback;
      return ref.read(appConfigValueProvider);
    }
  }

  /// เปิดบทสนทนาล่าสุดต่อ ถ้ายังไม่มีค่อยสร้างใหม่ (เซิร์ฟเวอร์เก่าเท่านั้น)
  ///
  /// ของเดิมยิง POST /conversations ทุกครั้งที่แตะแท็บ "แม่หมอ" → ห้องเปล่า
  /// งอกบนเซิร์ฟเวอร์ทุกครั้ง และผู้ใช้เสียบริบทที่คุยค้างไว้ ต่างจากเว็บที่คุยต่อห้องเดิมเสมอ
  Future<void> _openLatestOrStart() async {
    final epoch = _epoch;
    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      if (!mounted || epoch != _epoch) return;
      final list = await repo.listConversations();
      if (!mounted || epoch != _epoch) return;
      if (list.isNotEmpty) {
        await _resumeSession(list.first.id);
        return;
      }
    } catch (_) {
      // ดึงรายการไม่ได้ → ตกไปสร้างห้องใหม่ตามเดิม
    }
    if (!mounted || epoch != _epoch) return;
    await _startSession();
  }

  Future<void> _startSession({
    int? readingId,
    String? room,
    bool startNew = false,
  }) async {
    final epoch = _epoch;
    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      if (!mounted || epoch != _epoch) return;
      final res = await repo.startConversation(
        readingId: readingId,
        room: room,
        startNew: startNew,
      );
      if (!mounted || epoch != _epoch) return;

      setState(() {
        _applyConversation(res.conversation, emptyGreeting: null);
        _starting = false;
      });
      _scrollToEnd();
      ref.invalidate(chatConversationsProvider);
      _afterOpen(res.conversation);
    } on ApiException catch (e) {
      if (!mounted || epoch != _epoch) return;
      if (e.statusCode == 422 && e.reasonCode == 'room_closed') {
        _roomClosed(e.message);
        return;
      }
      if (e.statusCode == 423 && e.reasonCode == 'room_locked') {
        _roomLocked(e);
        return;
      }
      _offlineGreeting(e.message);
    } catch (_) {
      if (!mounted || epoch != _epoch) return;
      _offlineGreeting(null);
    }
  }

  /// เปิดห้องไม่ได้ (เน็ตล่ม) — ยังเปิดหน้าจอให้ใช้ได้พร้อมคำทักทายในเครื่อง
  /// ส่งข้อความแรกเมื่อไรค่อยลองเปิดห้องใหม่อีกครั้ง
  void _offlineGreeting(String? note) {
    setState(() {
      if (_messages.isEmpty) _messages.add(_Msg.bot(_room.quote));
      if (note != null && note.isNotEmpty) _messages.add(_Msg.system(note));
      _starting = false;
    });
  }

  Future<void> _resumeSession(int id) async {
    final epoch = _epoch;
    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      if (!mounted || epoch != _epoch) return;
      final convo = await repo.getConversation(id);
      if (!mounted || epoch != _epoch) return;

      setState(() {
        _applyConversation(convo, emptyGreeting: null);
        _starting = false;
      });
      _scrollToEnd();
      _afterOpen(convo);
    } catch (e) {
      // อย่าสร้างห้องใหม่เงียบ ๆ — ผู้ใช้จะเสียที่ค้างไว้และได้ห้องเปล่าเพิ่ม
      if (kDebugMode) debugPrint('[Chat] resume failed: $e');
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _messages.add(
          _Msg.system(
            '$_selfเปิดบทสนทนาเก่าไม่ได้ค่ะ · กดย้อนกลับแล้วลองอีกครั้งได้นะคะ',
          ),
        );
        _starting = false;
      });
    }
  }

  /// ห้องปิดอยู่ (422 room_closed) — บอกเหตุผลแล้วพากลับหน้าเลือกผู้พยากรณ์
  void _roomClosed(String message) {
    setState(() {
      _starting = false;
      _roomGone = true;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
      );
    context.go(Routes.rooms);
  }

  /// กำลังทำนายอยู่อีกห้อง (423 room_locked) — แผงพาไปห้องนั้น
  void _roomLocked(ApiException e) {
    final lock = RoomLock.fromJson(e.body?['lock']);
    final target = ref
        .read(roomsValueProvider)
        .room(lock?.room ?? OracleRoom.defaultKey);
    setState(() {
      _starting = false;
      _gate = _LockGate(message: e.message, room: target);
    });
  }

  /// หลังเปิดห้องสำเร็จ — เสียงทักห้อง · ห้องที่ทีมงานคุมอยู่ถามหาข้อความใหม่
  void _afterOpen(ChatConversation convo) {
    if (_soundOn) unawaited(_playGreet());
    if (convo.held) _startFeed();
  }

  void _applyConversation(ChatConversation c, {String? emptyGreeting}) {
    if (c.id > 0) _conversationId = c.id;
    _roomKey = c.room.key;
    _brief = c.personaKnown ? c.room : null;
    _messages
      ..clear()
      ..addAll(c.messages.map(_Msg.fromDto));
    if (_messages.isEmpty) {
      _messages.add(_Msg.bot(emptyGreeting ?? _room.quote));
    }
    _held = c.held;
    _applyQuota(c.quota);
    _applyStatus(c.status);
  }

  /// ซิงก์โควตา/ปุ่มลัด/สถานะจาก response ของ backend
  void _applyQuota(ChatQuota q) {
    if (q.dailyLimit != null) _dailyLimit = q.dailyLimit!;
    if (q.dailyLeft != null) _dailyLeft = q.dailyLeft!;
    if (q.cost != null) _cost = q.cost!;
    if (q.awaiting != null) _awaiting = q.awaiting!;
    if (q.suggestions != null) _suggestions = q.suggestions!;
    if (q.aiSuggestions != null) _aiSuggestions = q.aiSuggestions!;

    // 🔴 เชื่อ `blocked` ของเซิร์ฟเวอร์เท่านั้น ห้ามเดาเองจาก daily_left
    //
    // ChatPolicy::exhausted() คืน false เสมอเมื่อแชทเป็นโหมดเสียเงิน
    // (เพดานรายวันใช้กับโหมดฟรีอย่างเดียว) โค้ดเดิมปิดช่องพิมพ์ทันทีที่
    // daily_left <= 0 ลูกค้าที่พร้อมจ่ายรายข้อความจึงถูกล็อกออกจากแชท
    // ทั้งที่เซิร์ฟเวอร์อนุญาต — เสียรายได้โดยไม่มีใครเห็น error
    if (q.blocked != null) {
      _blocked = q.blocked!;
      _blockedReason = _blocked ? _dailyDoneReason : '';
    }

    // ราคาข้อความถัดไปก็ต้องมาจากเซิร์ฟเวอร์ ไม่ใช่ค่าที่แอพจำไว้
    if (q.nextCost != null) _cost = q.nextCost!;
  }

  void _applyStatus(ChatRoomStatus s) {
    final config = ref.read(appConfigValueProvider);
    _qa = config.has('qa_clock') ? s.qa : null;
    _freeAsk = config.has('free_ask') ? s.freeAsk : null;
    _qaExpiredHere = false;
    if (_qa == null || !_qa!.isOver()) _qaOverMessage = null;
    // 🛡 Play: ไม่มีบิลพร้อมเพย์ในแอพเด็ดขาด — เซิร์ฟเวอร์ไม่ส่งมาอยู่แล้ว กั้นซ้ำอีกชั้น
    // บิลค้างเป็นส่วนของระบบห้อง (A4) — เซิร์ฟเวอร์ที่ไม่ประกาศ `rooms` ไม่มีบิลแบบนี้
    final bill = config.has('rooms') ? s.pendingBill : null;
    _bill = (isPlayChannel || bill == null || bill.isExpired()) ? null : bill;
  }

  /* ══════════════════════ ส่งข้อความ ══════════════════════ */

  String _newIdempotencyKey() {
    final r = math.Random();
    return '${DateTime.now().microsecondsSinceEpoch}-'
        '${List.generate(4, (_) => r.nextInt(36).toRadixString(36)).join()}';
  }

  bool get _canType =>
      !_typing &&
      !_starting &&
      !_qaEnding &&
      _gate == null &&
      !_qaOver &&
      (!_blocked || _held);

  Future<void> _send({
    String? overrideText,
    String? reuseIdem,
    _Msg? replacing,
  }) async {
    final text = (overrideText ?? _controller.text).trim();
    if (text.isEmpty || !_canType) return;
    final epoch = _epoch;
    if (_listening) unawaited(_speech.stop());

    // คีย์เดิมเมื่อ "ลองใหม่" ข้อความเดิม → backend กันการตัดเงินซ้ำได้จริง
    // (จำเป็นมากเพราะ dio retry POST อัตโนมัติเมื่อต่อเซิร์ฟเวอร์ไม่ติด)
    final idem = reuseIdem ?? _newIdempotencyKey();

    // วงเล็บชัด ๆ ว่า cascade ทำงานกับผลของ ?? (ตัวเดิมตอน retry / ตัวใหม่ตอนส่งครั้งแรก)
    final mine = (replacing ?? _Msg.user(text))
      ..idempotencyKey = idem
      ..failed = false
      ..note = null;

    setState(() {
      if (replacing == null) _messages.add(mine);
      _typing = true;
    });
    if (overrideText == null) _controller.clear();
    _scrollToEnd();

    try {
      if (_conversationId == null) {
        await _startSession(
          readingId: widget.fromReadingId,
          room: _hasRooms && widget.fromReadingId == null ? _roomKey : null,
        );
        // เปิดห้องสำเร็จแทนคำทักออฟไลน์แล้ว ต้องเก็บฟองที่กำลังส่งไว้ด้วย
        if (mounted && epoch == _epoch && !_messages.contains(mine)) {
          setState(() => _messages.add(mine));
        }
      }
      if (!mounted || epoch != _epoch) return;
      // ห้องถูกล็อก (แผงพาไปห้องที่ทำนายอยู่) / ห้องปิด (กำลังกลับหน้าเลือกห้อง) — ไม่ใช่เน็ตล่ม
      if (_gate != null || _roomGone) {
        setState(() => _typing = false);
        return;
      }
      if (_conversationId == null) throw StateError('no conversation');

      final repo = await ref.read(chatRepositoryProvider.future);
      if (!mounted || epoch != _epoch) return;
      final res = await repo.send(
        conversationId: _conversationId!,
        text: text,
        idempotencyKey: idem,
      );
      if (!mounted || epoch != _epoch) return;

      setState(() {
        _typing = false;
        _suggestOpen = false;
        _applyQuota(res.quota);
        _applyStatus(res.status);
        if (res.held) {
          // ทีมงานคุมห้องอยู่ — ข้อความถึงทีมงานแล้ว ไม่มีฟองคำตอบจากบอท (ห้ามโชว์คำขอโทษสำเร็จรูป)
          _held = true;
          return;
        }
        // ข้อความของผู้พยากรณ์ + แพ็กเกจที่ยื่น (การ์ดกดเปิดไพ่ได้ในแอพ) — `reply` ที่ต่อรายการเป็น
        // ข้อความไว้ท้ายคำตอบมีไว้ให้แอพรุ่นเก่า รุ่นนี้ใช้ `message` + `offers` แทน
        final content = res.message?.content;
        final body = (content ?? res.reply).trim();
        _messages.add(
          _Msg.bot(
            body.isEmpty ? _busyReply() : body,
            id: res.message?.id,
            offers: res.offers,
            question: res.question,
            voiceUrl: res.replyVoiceUrl,
            staff: res.message?.isStaff ?? false,
          ),
        );
        // ไม่ได้คำตอบจริง (ระบบแน่น — ไม่คิดเงิน) → ให้กด "ลองส่งใหม่" ด้วยคีย์เดิมได้
        if (res.degraded || res.message == null && res.offers.isEmpty) {
          mine.failed = true;
        }
      });
      _scrollToEnd();
      ref.invalidate(chatConversationsProvider);
      if (res.held) {
        _startFeed();
        return;
      }
      final voice = _voiceOk ? res.replyVoiceUrl : null;
      if (voice != null && _soundOn && _foreground && _onTop) {
        unawaited(_voice.play(voice));
      }
      if (res.quota.balance != null) {
        ref.read(authControllerProvider.notifier).refresh();
      }
    } on ApiException catch (e) {
      if (!mounted || epoch != _epoch) return;
      await _handleSendError(e, mine);
    } catch (_) {
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _typing = false;
        mine.failed = true;
        _messages.add(
          _Msg.system(
            'เครือข่ายมีปัญหาค่ะ — กด "ลองส่งใหม่" ได้เลย ข้อความจะไม่ถูกส่งซ้ำซ้อน',
          ),
        );
      });
      _scrollToEnd();
    }
  }

  String _busyReply() =>
      'ขอโทษนะคะ ตอนนี้$_selfตอบไม่ทัน รอสักครู่แล้วกด "ลองส่งใหม่" ได้เลยค่ะ (ข้อความนี้ไม่คิดเครดิตนะคะ)';

  Future<void> _handleSendError(ApiException e, _Msg mine) async {
    switch (e.statusCode) {
      case 402: // เครดิตไม่พอ
        setState(() {
          _typing = false;
          _blocked = true;
          _blockedReason = 'เครดิตไม่พอ — เติมเครดิตแล้วคุยต่อได้เลยค่ะ';
          _messages.add(_Msg.system(e.message));
        });
        _scrollToEnd();
        // ใช้ชีทที่เติมเงินจบในแชท (เลือกยอด → QR → poll → แนบสลิป)
        // เส้นทางที่ลูกค้าเจอบ่อยที่สุดคือ "ส่งข้อความแล้วเงินไม่พอ" ต้องไม่พาออกจากแชท
        // (ทีมบันทึกไว้เองว่าลูกค้ากลุ่มผู้สูงอายุหลุดกลางทาง)
        await _showTopUpFlow();
        return;

      case 429:
        if (e.reasonCode == 'daily_limit') {
          // ครบโควตาคุยฟรีวันนี้ — ไม่ใช่ error ของผู้ใช้ ชวนไปทางอื่นต่อ
          setState(() {
            _typing = false;
            _dailyLeft = 0;
            _blocked = true;
            _blockedReason = _dailyDoneReason;
            _messages.add(_Msg.system(e.message));
          });
        } else {
          setState(() {
            _typing = false;
            mine.failed = true;
            _messages.add(
              _Msg.system(
                'พิมพ์เร็วเกินไปนิดนะคะ — รอสักครู่แล้วกด "ลองส่งใหม่" ได้เลย',
              ),
            );
          });
        }
        _scrollToEnd();
        return;

      case 409:
        if (e.reasonCode == 'qa_over') {
          // หมดเวลาถามต่อ/กด "พอแล้ว" ไปแล้ว — ข้อความนี้ไม่ถูกส่ง ไม่คิดเงิน
          setState(() {
            _typing = false;
            _qa = ChatClock.fromJson(e.body?['qa']) ?? _qa;
            _qaExpiredHere = true;
            _qaOverMessage = e.message;
            mine.note = 'ยังไม่ได้ส่ง — หมดเวลาถามต่อแล้ว';
          });
          return;
        }
        if (e.reasonCode == 'busy_other') {
          // ส่งจากอีกเครื่อง/แท็บอยู่ — ข้อความนี้ยังไม่ถูกส่ง ไม่คิดเงิน · ลองใหม่ด้วยคีย์เดิม
          final serverSaid = e.body?['message'] is String;
          setState(() {
            _typing = false;
            mine.failed = true;
            _messages.add(
              _Msg.system(
                serverSaid
                    ? e.message
                    : 'ส่งจากอีกเครื่องอยู่ ลองส่งใหม่อีกครั้ง',
              ),
            );
          });
          _scrollToEnd();
          return;
        }
        // in_flight — ข้อความเดิมกำลังส่งอยู่ (idempotency guard) คำตอบอยู่ที่เซิร์ฟเวอร์
        setState(() => _typing = false);
        await _syncFromServer();
        return;

      case 422:
        if (e.reasonCode == 'room_closed') {
          setState(() => _typing = false);
          _roomClosed(e.message);
          return;
        }
        break;

      case 401:
        setState(() {
          _typing = false;
          mine.failed = true;
          _messages.add(
            _Msg.system('session หมดอายุค่ะ — กรุณาเข้าสู่ระบบใหม่'),
          );
        });
        _scrollToEnd();
        return;
    }
    setState(() {
      _typing = false;
      mine.failed = true;
      _messages.add(_Msg.system(e.message));
    });
    _scrollToEnd();
  }

  /// ดึงบทสนทนาจากเซิร์ฟเวอร์มาทับ — ใช้ตอนเจอ 409 in_flight ซึ่งแปลว่าข้อความถูกส่ง
  /// ไปแล้วจริง คำตอบจึงอยู่ฝั่งเซิร์ฟเวอร์ ไม่ควรให้ผู้ใช้กดส่งซ้ำ
  Future<void> _syncFromServer() async {
    final id = _conversationId;
    if (id == null) return;
    final epoch = _epoch;
    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      if (!mounted || epoch != _epoch) return;
      final convo = await repo.getConversation(id);
      if (!mounted || epoch != _epoch) return;
      setState(() => _applyConversation(convo));
      _scrollToEnd();
      if (convo.held) _startFeed();
    } catch (_) {
      if (!mounted || epoch != _epoch) return;
      setState(
        () => _messages.add(
          _Msg.system(
            'ข้อความก่อนหน้ากำลังส่งอยู่ค่ะ รอสักครู่แล้วแตะ "ดูคำตอบล่าสุด" อีกครั้งนะคะ',
          ),
        ),
      );
    }
  }

  /* ══════════════════════ ทีมงานคุมห้อง (feed) ══════════════════════ */

  int get _lastId => _messages.fold<int>(0, (m, x) => math.max(m, x.id ?? 0));

  void _startFeed() {
    if (!ref.read(appConfigValueProvider).has('chat_feed') ||
        _conversationId == null) {
      return;
    }
    _feedUntil = DateTime.now().add(_feedFor);
    _scheduleFeed();
  }

  void _scheduleFeed() {
    _feedTimer?.cancel();
    _feedTimer = null;
    final until = _feedUntil;
    if (!mounted || until == null || !_foreground || !_onTop) return;
    if (DateTime.now().isAfter(until)) {
      _stopFeed();
      return;
    }
    _feedTimer = Timer(_feedEvery, _pollFeed);
  }

  void _stopFeed() {
    _feedTimer?.cancel();
    _feedTimer = null;
    _feedUntil = null;
  }

  Future<void> _pollFeed() async {
    final id = _conversationId;
    if (!mounted || id == null || !_foreground || !_onTop) return;
    // ระหว่างส่งข้อความอยู่ไม่ถาม — กันฟองเดียวกันขึ้นซ้ำ
    if (_feedBusy || _typing) {
      _scheduleFeed();
      return;
    }
    final epoch = _epoch;
    _feedBusy = true;
    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      if (!mounted || epoch != _epoch) return;
      final feed = await repo.feed(id, after: _lastId);
      if (!mounted || epoch != _epoch || !_foreground || !_onTop) return;
      final known = {
        for (final m in _messages)
          if (m.id != null) m.id!,
      };
      final fresh = feed.messages
          .where((m) => m.id != null && !known.contains(m.id))
          .toList();
      setState(() {
        _messages.addAll(fresh.map(_Msg.fromDto));
        _held = feed.held;
      });
      if (fresh.isNotEmpty) {
        _scrollToEnd();
        _stopFeed();
        return;
      }
      if (!feed.held) {
        _stopFeed();
        return;
      }
    } on ApiException catch (e) {
      if (!mounted || epoch != _epoch) return;
      // เซิร์ฟเวอร์ไม่มี feed / ไม่ใช่ห้องของเรา — เลิกถาม
      if (e.statusCode == 404 || e.statusCode == 403) {
        _stopFeed();
        return;
      }
    } catch (_) {
      // เน็ตสะดุด — รอบหน้าถามใหม่เอง
    } finally {
      _feedBusy = false;
    }
    if (mounted && epoch == _epoch) _scheduleFeed();
  }

  /* ══════════════════════ นาฬิกาถามต่อ ══════════════════════ */

  Future<void> _confirmEndQa() async {
    final id = _conversationId;
    if (id == null ||
        _qaEnding ||
        !ref.read(appConfigValueProvider).has('qa_clock')) {
      return;
    }
    final epoch = _epoch;
    setState(() => _qaEnding = true);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'พอแล้วใช่ไหมคะ?',
          style: baiJamjuree(size: 17, color: JuntraColors.gold),
        ),
        content: Text(
          'จบเวลาถามต่อของไพ่ชุดนี้ตอนนี้เลย — หลังจากนี้ถามต่อในห้องนี้ไม่ได้แล้ว '
          'แต่คุยเรื่องอื่นหรือเปิดไพ่ชุดใหม่กับ$_selfได้เสมอค่ะ',
          style: const TextStyle(
            color: JuntraColors.textLavender,
            fontSize: 13,
            height: 1.55,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'ถามต่อก่อน',
              style: TextStyle(color: JuntraColors.textFaint),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'พอแล้ว',
              style: TextStyle(color: JuntraColors.gold),
            ),
          ),
        ],
      ),
    );
    if (!mounted || epoch != _epoch) return;
    if (ok != true || id != _conversationId) {
      setState(() => _qaEnding = false);
      return;
    }
    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      if (!mounted || epoch != _epoch) return;
      final res = await repo.qaEnd(id);
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _qaEnding = false;
        _qa = res.qa ?? _qa;
        _qaExpiredHere = true;
        // คำลา (กดซ้ำได้ null — ไม่มีคำลาซ้ำ)
        final bye = res.message;
        if (bye != null &&
            !_messages.any((m) => m.id != null && m.id == bye.id)) {
          _messages.add(_Msg.fromDto(bye));
        }
      });
      _scrollToEnd();
    } on ApiException catch (e) {
      if (!mounted || epoch != _epoch) return;
      setState(() => _qaEnding = false);
      _snack(e.message);
    } catch (_) {
      if (!mounted || epoch != _epoch) return;
      setState(() => _qaEnding = false);
      _snack('เครือข่ายมีปัญหาค่ะ ลองกด "พอแล้ว" อีกครั้งนะคะ');
    }
  }

  /// "คุยเรื่องอื่น" — ห้องใหม่ของผู้พยากรณ์คนเดิม (`/chat?room=<key>&new=1`)
  void _openFreshRoom() {
    final key = _roomKey;
    final target = '${Routes.chat}?room=$key&new=1';
    final here = GoRouterState.of(context).uri.toString();
    if (here != target) {
      context.go(target);
      return;
    }
    // อยู่ที่ URL นี้แล้ว (กดซ้ำ) — go_router ไม่สร้างหน้าใหม่ให้ เปิดห้องใหม่ในที่เดิม
    _resetRoom(key);
    unawaited(_startSession(room: _hasRooms ? key : null, startNew: true));
  }

  void _openRoomPackages() => RoomPackagesSheet.show(context, _room);

  /* ══════════════════════ บิลค้าง ══════════════════════ */

  Future<void> _payBill() async {
    final bill = _bill;
    if (bill == null || isPlayChannel || _paymentOpen) return;
    final epoch = _epoch;
    _paymentOpen = true;
    bool? paid;
    try {
      paid = await ChatTopUpSheet.show(context, resume: bill, selfName: _self);
    } finally {
      _paymentOpen = false;
    }
    if (paid == true && mounted && epoch == _epoch) {
      setState(() {
        _bill = null;
        _blocked = false;
        _blockedReason = '';
      });
      ref.read(authControllerProvider.notifier).refresh();
      unawaited(_syncFromServer());
    }
  }

  /* ══════════════════════ เสียง · ไมค์ ══════════════════════ */

  Future<void> _toggleSound() async {
    final on = !_soundOn;
    setState(() => _soundOn = on);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSoundPref, on);
    if (!mounted || on != _soundOn) return;
    if (on) {
      unawaited(_playGreet());
    } else {
      unawaited(_voice.stop());
    }
  }

  /// เสียงทักห้อง (`media.voice.room_greet`) — ครั้งเดียวต่อการเข้าห้อง
  Future<void> _playGreet() async {
    if (_greeted) return;
    final epoch = _epoch;
    RoomsState rooms;
    try {
      rooms = await ref
          .read(roomsProvider.future)
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      if (!mounted || epoch != _epoch) return;
      rooms = ref.read(roomsValueProvider);
    }
    if (!mounted ||
        epoch != _epoch ||
        !_soundOn ||
        _greeted ||
        !_foreground ||
        !_onTop) {
      return;
    }
    final url = rooms.room(_roomKey).media.voiceFor('room_greet');
    if (url == null) return;
    _greeted = true;
    await _voice.play(url);
  }

  Future<void> _toggleReplyVoice(String url) async {
    if (_voice.current.value == url) {
      await _voice.stop();
      return;
    }
    final ok = await _voice.play(url);
    if (!ok && mounted) _snack('เปิดเสียงไม่ได้ตอนนี้ค่ะ ลองใหม่อีกครั้งนะคะ');
  }

  Future<void> _toggleMic() async {
    if (_micStarting) return;
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final epoch = _epoch;
    setState(() => _micStarting = true);
    _micBase = _controller.text.trimRight();
    final result = await _speech.start(
      onText: (words, _) {
        if (!mounted || epoch != _epoch || !_foreground || !_onTop) return;
        // ข้อความที่ฟังได้วางต่อท้ายที่พิมพ์ไว้ — ลูกค้าตรวจ/แก้ก่อนกดส่งเอง (ไม่ส่งเอง)
        final text = [
          _micBase,
          words.trim(),
        ].where((t) => t.isNotEmpty).join(' ');
        _controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      },
      onStopped: () {
        if (mounted && epoch == _epoch && _listening) {
          setState(() => _listening = false);
        }
      },
    );
    if (!mounted || epoch != _epoch || !_foreground || !_onTop) return;
    setState(() => _micStarting = false);
    switch (result) {
      case SpeechStart.listening:
        setState(() => _listening = _speech.isListening);
      case SpeechStart.cancelled:
        setState(() => _listening = false);
      case SpeechStart.denied:
        _snack('อนุญาตให้ใช้ไมโครโฟนก่อนนะคะ แล้วแตะไมค์อีกครั้ง');
      case SpeechStart.unavailable:
        setState(() {
          _listening = false;
          _micHidden = true;
        });
        _snack('เครื่องนี้ฟังเสียงไม่ได้ตอนนี้ค่ะ พิมพ์แทนได้เลยนะคะ');
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
      );
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll
            .position
            .maxScrollExtent, // เดิมบวก 80 = overscroll glow ทุกครั้ง
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  /* ══════════════════════ build ══════════════════════ */

  @override
  Widget build(BuildContext context) {
    // สลับผู้ใช้/ออกจากระบบระหว่างอยู่ในห้อง — ห้ามเห็นห้องของคนก่อน ห้าม poll ต่อในนามคนก่อน
    ref.listen<String?>(sessionUserIdProvider, (prev, next) {
      if (prev == next) return;
      _resetRoom(OracleRoom.normalize(widget.room));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _bootstrap();
      });
    });

    final config = ref.watch(appConfigValueProvider);
    final rooms = config.has('rooms')
        ? ref.watch(roomsValueProvider)
        : RoomsState.legacy;
    final room = rooms.room(_roomKey);
    final brief = _brief;
    final name = brief?.name ?? room.name;
    final short = brief?.short ?? room.short;
    final accent = brief?.accent ?? room.accent;
    final imageUrl = brief?.imageUrl ?? room.imageUrl;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final qaOver = _qaOver;
    final billBlocks = _bill?.blocks ?? false;
    final voiceOk = config.has('voice_premium');

    return Scaffold(
      bottomNavigationBar: const JuntraTabBar(currentIndex: 2),
      body: Stack(
        children: [
          const StarryBackground(density: 30, intensity: 0.4),
          SafeArea(
            child: Column(
              children: [
                _ChatHeader(
                  roomKey: _roomKey,
                  name: name,
                  imageUrl: imageUrl,
                  accent: accent,
                  status: _held
                      ? 'เจ้าหน้าที่ดูแลห้องนี้อยู่ค่ะ'
                      : _typing
                      ? _busyLine(_roomKey)
                      : 'พร้อมรับฟังอยู่ค่ะ',
                  soundAvailable: room.media.voice.isNotEmpty,
                  soundOn: _soundOn,
                  onSound: _toggleSound,
                  onNewChat:
                      _starting ||
                          _typing ||
                          _qaEnding ||
                          _newChatConfirming ||
                          _gate != null
                      ? null
                      : _confirmNewChat,
                ),
                // ฉากผู้พยากรณ์ — ยุบตอนพิมพ์ (คีย์บอร์ดเปิด) ให้เหลือที่ให้ข้อความ
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: keyboardOpen || _gate != null
                      ? const SizedBox(width: double.infinity)
                      : _StageStrip(
                          room: room,
                          imageUrl: imageUrl,
                          accent: accent,
                          active: !keyboardOpen && _gate == null,
                        ),
                ),
                if (_qa != null || _freeAsk != null)
                  _ClockRow(
                    qa: _qa,
                    freeAsk: _freeAsk,
                    qaOver: qaOver,
                    ending: _qaEnding,
                    busy: _typing,
                    onEnd: _confirmEndQa,
                    onQaExpired: () {
                      if (mounted && !_qaExpiredHere) {
                        setState(() => _qaExpiredHere = true);
                      }
                    },
                  ),
                if (_starting)
                  const LinearProgressIndicator(
                    minHeight: 1.5,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      JuntraColors.gold,
                    ),
                  ),
                if (_bill != null && !isPlayChannel)
                  _BillBanner(
                    bill: _bill!,
                    onPay: _payBill,
                    onExpired: () {
                      if (mounted) setState(() => _bill = null);
                    },
                  ),
                if (_gate == null &&
                    (_dailyLimit > 0 || _cost > 0) &&
                    !keyboardOpen)
                  _QuotaBar(
                    dailyLimit: _dailyLimit,
                    dailyLeft: _dailyLeft,
                    cost: _cost,
                  ),
                Expanded(
                  child: _gate != null
                      ? _LockPanel(
                          gate: _gate!,
                          onGo: () {
                            final room = _gate?.room.key;
                            if (room != null) context.go('${Routes.chat}?room=$room');
                          },
                          onRooms: () => context.go(Routes.rooms),
                        )
                      : ValueListenableBuilder<String?>(
                          valueListenable: _voice.current,
                          builder: (context, playing, _) => ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                            itemCount: _messages.length + (_typing ? 1 : 0),
                            itemBuilder: (_, i) {
                              if (_typing && i == _messages.length) {
                                return _TypingBubble(
                                  roomKey: _roomKey,
                                  imageUrl: imageUrl,
                                  accent: accent,
                                );
                              }
                              final m = _messages[i];
                              final ai = !m.fromUser && !m.isSystem && !m.staff;
                              return _Bubble(
                                msg: m,
                                roomKey: _roomKey,
                                roomName: short,
                                imageUrl: imageUrl,
                                accent: accent,
                                offersDisabledReason: billBlocks
                                    ? 'มีบิลค้างจ่ายอยู่ — จ่ายบิลให้เสร็จก่อน แล้วเปิดไพ่ต่อได้เลยค่ะ'
                                    : null,
                                onOffer: _openOffer,
                                // รายงานได้เฉพาะคำตอบของ AI (Google Play: AI-Generated Content policy)
                                onReport: ai && m.id != null
                                    ? () => ReportContentSheet.show(
                                        context,
                                        subject: ReportSubject.chatMessage,
                                        subjectId: m.id!,
                                      )
                                    : null,
                                onRetry: m.failed && !qaOver
                                    ? () => _send(
                                        overrideText: m.text,
                                        reuseIdem: m.idempotencyKey,
                                        replacing: m,
                                      )
                                    : null,
                                onCopy: m.fromUser || m.isSystem
                                    ? null
                                    : () => _copy(m.text),
                                voicePlaying:
                                    voiceOk &&
                                    m.voiceUrl != null &&
                                    playing == m.voiceUrl,
                                onVoice: !voiceOk || m.voiceUrl == null
                                    ? null
                                    : () => _toggleReplyVoice(m.voiceUrl!),
                              );
                            },
                          ),
                        ),
                ),
                if (_gate == null && _held)
                  _HeldLine(
                    polling: _feedUntil != null,
                    onRefresh: _syncFromServer,
                  ),
                if (_gate == null && qaOver)
                  _QaOverPanel(
                    message: _qaOverText,
                    roomShort: short,
                    onPackages: _openRoomPackages,
                    onFresh: _openFreshRoom,
                  )
                else if (_gate == null && !_held)
                  _SuggestionStrip(
                    selfName: short,
                    suggestions: _suggestions,
                    aiSuggestions: _aiSuggestions,
                    awaiting: _awaiting,
                    open: _suggestOpen,
                    blocked: _blocked,
                    blockedReason: _blockedReason,
                    busy: _typing || _starting,
                    onOpen: () => setState(() => _suggestOpen = true),
                    onPick: (prompt) => _send(overrideText: prompt),
                    onTopics: _showTopics,
                    onTopUp: _showTopUpFlow,
                  ),
                if (_gate == null)
                  _InputBar(
                    controller: _controller,
                    onSend: _send,
                    enabled: _canType,
                    hint: 'พิมพ์ข้อความถึง$short...',
                    lockedReason: qaOver
                        ? 'หมดเวลาถามต่อของไพ่ชุดนี้แล้วค่ะ'
                        : (_blocked && !_held)
                        ? _blockedReason
                        : null,
                    showMic: !_micHidden && !qaOver,
                    listening: _listening,
                    onMic: _micStarting ? () {} : _toggleMic,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// สถานะ "กำลังตอบ" ของแต่ละห้อง (config/chat_rooms.php → busy) — ไม่อ้างเวลาตอบที่ระบบไม่ได้รับประกัน
  static String _busyLine(String room) => switch (room) {
    'busaba' => 'บุษบากำลังดูไพ่ให้อยู่น้า…',
    'kunsai' => 'แม่หมอกำลังส่องดูอยู่ ตั้งสติรอก่อนนะคะ…',
    _ => 'แม่หมอกำลังเพ่งไพ่ให้คุณอยู่…',
  };

  /// กางหมวดคำถาม 24 ข้อ — เลือกแล้วส่งเป็นข้อความทันที
  Future<void> _showTopics() async {
    final prompt = await ChatTopicsSheet.show(context, selfName: _self);
    if (prompt == null || !mounted) return;
    await _send(overrideText: prompt);
  }

  /// เติมเครดิตจบในแชท — สำเร็จแล้วปลดล็อกช่องพิมพ์ทันทีไม่ต้องออกจากหน้า
  Future<void> _showTopUpFlow() async {
    if (_paymentOpen) return;
    final epoch = _epoch;
    _paymentOpen = true;
    try {
      // แอพบน Google Play เติมเครดิตผ่าน Google Play Billing เท่านั้น (ห้ามพร้อมเพย์ในแอพ Play)
      if (isPlayChannel) {
        var credited = false;
        await showPlayCreditsSheet(context, onCredited: () => credited = true);
        if (credited && mounted && epoch == _epoch) {
          setState(() {
            _blocked = false;
            _blockedReason = '';
          });
          ref.read(authControllerProvider.notifier).refresh();
        }
        return;
      }
      final paid = await ChatTopUpSheet.show(context, selfName: _self);
      if (paid == true && mounted && epoch == _epoch) {
        setState(() {
          _blocked = false;
          _blockedReason = '';
        });
        ref.read(authControllerProvider.notifier).refresh();
      }
    } finally {
      _paymentOpen = false;
    }
  }

  /// แพ็กเกจที่ผู้พยากรณ์ยื่นในแชท → เข้าซีนสับไพ่ในแอพ
  void _openOffer(ChatOffer o, String? question) {
    if (o.locked || (_bill?.blocks ?? false)) return;
    if (o.kind == 'deep') {
      if (ref.read(appConfigValueProvider).isOpen('deep')) {
        context.pushOnce(Routes.deep);
      }
      return;
    }
    final spread = o.spread;
    if (spread == null || spread.isEmpty) return;
    final q = question == null || question.trim().isEmpty
        ? ''
        : '&q=${Uri.encodeQueryComponent(question.trim())}';
    context.pushOnce(
      '${Routes.shuffle}?spread=${Uri.encodeQueryComponent(spread)}$q',
    );
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('คัดลอกคำตอบแล้ว'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmNewChat() async {
    if (_newChatConfirming || _typing || _starting) return;
    final epoch = _epoch;
    setState(() => _newChatConfirming = true);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'เริ่มบทสนทนาใหม่?',
          style: baiJamjuree(size: 17, color: JuntraColors.gold),
        ),
        content: const Text(
          'บทสนทนาปัจจุบันจะถูกเก็บไว้ในประวัติ เปิดกลับมาอ่านได้ตลอดค่ะ',
          style: TextStyle(
            color: JuntraColors.textLavender,
            fontSize: 13,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'ยกเลิก',
              style: TextStyle(color: JuntraColors.textFaint),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'เริ่มใหม่',
              style: TextStyle(color: JuntraColors.gold),
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _newChatConfirming = false);
    if (ok != true || epoch != _epoch) return;

    // เปิดห้องใหม่ในที่เดิม (ห้องเดิมของผู้พยากรณ์คนเดิม) — เซิร์ฟเวอร์เก่าได้ห้องแม่หมอใหม่แบบเดิม
    final key = _roomKey;
    final blockedForToday = _dailyLimit > 0 && _dailyLeft <= 0;
    _resetRoom(key);
    setState(() {
      _blocked = blockedForToday;
      _blockedReason = blockedForToday ? _dailyDoneReason : '';
    });
    await _startSession(room: _hasRooms ? key : null, startNew: true);
  }
}

/* ══════════════════════ models ══════════════════════ */

class _Msg {
  _Msg({
    required this.text,
    required this.fromUser,
    this.isSystem = false,
    this.id,
    this.offers = const [],
    this.question,
    this.staff = false,
    this.voiceUrl,
  });

  final String text;
  final bool fromUser;

  /// id ของข้อความบนเซิร์ฟเวอร์ — ใช้รายงานเนื้อหาและกันข้อความ feed ซ้ำ (null = ข้อความในเครื่อง)
  final int? id;

  /// แพ็กเกจไพ่ที่ผู้พยากรณ์ยื่นในข้อความนี้ (กดแล้วเข้าซีนสับไพ่ในแอพ)
  final List<ChatOffer> offers;

  /// คำถามที่ลูกค้าพิมพ์ตอนผู้พยากรณ์ยื่นแพ็กเกจ — เติมให้ในหน้าสับไพ่
  final String? question;

  /// ข้อความจาก "ระบบ" (โควตาหมด / เน็ตล่ม) — ต้องหน้าตาไม่เหมือนคำพูดผู้พยากรณ์
  /// ไม่งั้นผู้ใช้เข้าใจว่าผู้พยากรณ์พูดเรื่องระบบเอง
  final bool isSystem;

  /// ทีมงานพิมพ์ในนามเจ้าหน้าที่ (`admin_as == admin`)
  final bool staff;

  /// เสียงคำตอบ (พรีเมียม)
  final String? voiceUrl;

  bool failed = false;
  String? idempotencyKey;

  /// บรรทัดเล็กใต้ข้อความ (เช่น "ยังไม่ได้ส่ง — หมดเวลาถามต่อแล้ว")
  String? note;

  factory _Msg.user(String t, {int? id}) =>
      _Msg(text: t, fromUser: true, id: id);
  factory _Msg.bot(
    String t, {
    int? id,
    List<ChatOffer> offers = const [],
    String? question,
    String? voiceUrl,
    bool staff = false,
  }) => _Msg(
    text: t,
    fromUser: false,
    id: id,
    offers: offers,
    question: question,
    voiceUrl: voiceUrl,
    staff: staff,
  );
  factory _Msg.system(String t) =>
      _Msg(text: t, fromUser: false, isSystem: true);

  factory _Msg.fromDto(ChatMessageDto m) => m.fromUser
      ? _Msg.user(m.content, id: m.id)
      : _Msg.bot(
          m.content,
          id: m.id,
          offers: m.offers,
          staff: m.isStaff,
          voiceUrl: m.replyVoiceUrl,
        );
}

/// ห้องถูกล็อกระหว่างทำนายอยู่อีกห้อง (423)
class _LockGate {
  const _LockGate({required this.message, required this.room});
  final String message;
  final OracleRoom room;
}

/* ══════════════════════ widgets ══════════════════════ */

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.roomKey,
    required this.name,
    required this.imageUrl,
    required this.accent,
    required this.status,
    required this.soundAvailable,
    required this.soundOn,
    required this.onSound,
    this.onNewChat,
  });

  final String roomKey;
  final String name;
  final String? imageUrl;
  final Color accent;
  final String status;
  final bool soundAvailable;
  final bool soundOn;
  final VoidCallback onSound;
  final VoidCallback? onNewChat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(2, 6, 4, 6),
      decoration: BoxDecoration(
        color: JuntraColors.bgDeepest.withValues(alpha: 0.4),
        border: Border(
          bottom: BorderSide(color: accent.withValues(alpha: 0.25)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.chevron_left,
              color: JuntraColors.gold,
              size: 28,
            ),
            tooltip: 'ย้อนกลับ',
            onPressed: () =>
                context.canPop() ? context.pop() : context.go(Routes.home),
          ),
          RoomAvatar(
            roomKey: roomKey,
            imageUrl: imageUrl,
            size: 38,
            accent: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: baiJamjuree(size: 15.5),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const AiBadge(),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const OnlineDot(),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: JuntraColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (soundAvailable)
            IconButton(
              icon: Icon(
                soundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                color: soundOn ? JuntraColors.gold : JuntraColors.textMuted,
                size: 20,
              ),
              tooltip: soundOn ? 'ปิดเสียงห้อง' : 'เปิดเสียงห้อง',
              visualDensity: VisualDensity.compact,
              onPressed: onSound,
            ),
          IconButton(
            icon: const Icon(
              Icons.add_comment_outlined,
              color: JuntraColors.textMuted,
              size: 20,
            ),
            tooltip: 'เริ่มบทสนทนาใหม่',
            visualDensity: VisualDensity.compact,
            onPressed: onNewChat,
          ),
          IconButton(
            icon: const Icon(
              Icons.history,
              color: JuntraColors.textMuted,
              size: 21,
            ),
            tooltip: 'บทสนทนาเก่า',
            visualDensity: VisualDensity.compact,
            onPressed: () => context.pushOnce(Routes.chatConversations),
          ),
          const SizedBox(width: StarryBackground.logoReserve),
        ],
      ),
    );
  }
}

/// แถบฉากผู้พยากรณ์ใต้หัวห้อง — คลิป idle / ภาพนิ่งหายใจ + คำโปรยของห้อง
class _StageStrip extends StatelessWidget {
  const _StageStrip({
    required this.room,
    required this.imageUrl,
    required this.accent,
    required this.active,
  });

  final OracleRoom room;
  final String? imageUrl;
  final Color accent;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final h = (MediaQuery.sizeOf(context).height * 0.17).clamp(96.0, 150.0);
    return Container(
      height: h,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.22),
            blurRadius: 22,
            spreadRadius: -6,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(JuntraRadius.card),
        child: Stack(
          fit: StackFit.expand,
          children: [
            RoomStage(
              roomKey: room.key,
              loops: room.media.loops,
              posterUrl: room.media.stillUrl ?? imageUrl,
              active: active,
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 8,
              child: Text(
                room.eyebrow,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: accent,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// แถวนาฬิกา — เวลาถามต่อ · พรีเมียม · "พอแล้ว" · เวลาถามฟรี
class _ClockRow extends StatelessWidget {
  const _ClockRow({
    required this.qa,
    required this.freeAsk,
    required this.qaOver,
    required this.ending,
    required this.busy,
    required this.onEnd,
    required this.onQaExpired,
  });

  final ChatClock? qa;
  final ChatClock? freeAsk;
  final bool qaOver;
  final bool ending;
  final bool busy;
  final VoidCallback onEnd;
  final VoidCallback onQaExpired;

  @override
  Widget build(BuildContext context) {
    final qa = this.qa;
    final free = freeAsk;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (qa != null) ChatClockChip(clock: qa, onExpired: onQaExpired),
          if (qa != null && qa.premium && !qaOver)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [JuntraColors.purple, JuntraColors.magenta],
                ),
                borderRadius: BorderRadius.circular(JuntraRadius.chip),
              ),
              child: const Text(
                '🎙️ พรีเมียม',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (qa != null && !qaOver)
            OutlinedButton(
              onPressed: ending || busy ? null : onEnd,
              style: OutlinedButton.styleFrom(
                foregroundColor: JuntraColors.goldLight,
                side: const BorderSide(color: JuntraColors.line),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(ending ? 'กำลังจบ…' : 'พอแล้ว'),
            ),
          if (free != null) ChatClockChip(clock: free, free: true),
        ],
      ),
    );
  }
}

/// บิลเติมเงินค้างของห้อง (เว็บ "บิลเลขที่ …") — ช่อง APK เท่านั้น
class _BillBanner extends StatelessWidget {
  const _BillBanner({
    required this.bill,
    required this.onPay,
    required this.onExpired,
  });

  final ChatPendingBill bill;
  final VoidCallback onPay;
  final VoidCallback onExpired;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
      decoration: BoxDecoration(
        color: JuntraColors.gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(JuntraRadius.input),
        border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.receipt_long_outlined,
            color: JuntraColors.gold,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ยอดที่ต้องโอนจริง (มีเศษสตางค์ไว้จับคู่ SMS) — ตรงกับที่เว็บโชว์บนบิลเดียวกัน
                Text(
                  'บิลเลขที่ ${bill.ref} · ฿${bill.payableAmount.toStringAsFixed(2)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: JuntraColors.textCream,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (bill.expiresAt != null)
                  SecondTicker(
                    builder: (context, now) {
                      final left = bill.secondsLeft(now) ?? 0;
                      if (left <= 0) {
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => onExpired(),
                        );
                      }
                      return Text(
                        bill.hasSlip
                            ? 'ได้รับสลิปแล้ว กำลังตรวจสอบให้นะคะ'
                            : 'จ่ายได้อีก ${ChatClock.format(left)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: JuntraColors.textMuted,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      );
                    },
                  )
                else if (bill.hasSlip)
                  const Text(
                    'ได้รับสลิปแล้ว กำลังตรวจสอบให้นะคะ',
                    style: TextStyle(
                      fontSize: 11,
                      color: JuntraColors.textMuted,
                    ),
                  ),
                if (bill.blocks)
                  const Text(
                    'จ่ายบิลนี้ให้เสร็จก่อน แล้วเปิดไพ่ต่อได้เลยค่ะ',
                    style: TextStyle(fontSize: 11, color: JuntraColors.goldMid),
                  ),
              ],
            ),
          ),
          // แนบสลิปแล้ว = ลูกค้าโอนแล้ว รอตรวจ — ห้ามชวนให้โอนอีก
          if (!bill.hasSlip)
            TextButton(
              onPressed: onPay,
              style: TextButton.styleFrom(
                foregroundColor: JuntraColors.gold,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: const Text('ดู QR จ่ายต่อ'),
            ),
        ],
      ),
    );
  }
}

/// ป้ายโควตาคุยฟรี / เครดิต — ให้ตรงกับแถบเดียวกันบนเว็บ
class _QuotaBar extends StatelessWidget {
  const _QuotaBar({
    required this.dailyLimit,
    required this.dailyLeft,
    required this.cost,
  });

  final int dailyLimit;
  final int dailyLeft;
  final double cost;

  @override
  Widget build(BuildContext context) {
    final free = cost <= 0;
    final low = free ? dailyLeft <= 3 : false;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: (low ? JuntraColors.goldMid : JuntraColors.gold).withValues(
          alpha: 0.08,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: JuntraColors.gold.withValues(alpha: low ? 0.5 : 0.2),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            free ? Icons.auto_awesome : Icons.account_balance_wallet_outlined,
            size: 14,
            color: JuntraColors.gold,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              free
                  ? 'คุยฟรีวันนี้ $dailyLeft / $dailyLimit ข้อความ · รีเซ็ตทุกเที่ยงคืน'
                  : 'หักครั้งละ ${formatCredits(cost)} ต่อข้อความ',
              style: const TextStyle(
                fontSize: 11.5,
                color: JuntraColors.textLavender,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// แผงแทนแชทเมื่อห้องถูกล็อก (กำลังทำนายอยู่อีกห้อง)
class _LockPanel extends StatelessWidget {
  const _LockPanel({
    required this.gate,
    required this.onGo,
    required this.onRooms,
  });

  final _LockGate gate;
  final VoidCallback onGo;
  final VoidCallback onRooms;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RoomAvatar(
              roomKey: gate.room.key,
              imageUrl: gate.room.imageUrl,
              size: 76,
              accent: gate.room.accent,
            ),
            const SizedBox(height: 16),
            Icon(Icons.lock_clock_outlined, color: gate.room.accent, size: 26),
            const SizedBox(height: 10),
            Text(
              gate.message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: JuntraColors.textLavender,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 20),
            GoldButton(
              label: 'ไปห้อง${gate.room.short}',
              icon: const Icon(Icons.arrow_forward),
              onPressed: onGo,
            ),
            const SizedBox(height: 10),
            GhostButton(label: 'กลับไปเลือกผู้พยากรณ์', onPressed: onRooms),
          ],
        ),
      ),
    );
  }
}

/// บรรทัดสถานะเงียบ ๆ เมื่อทีมงานคุมห้อง — แทนคำขอโทษสำเร็จรูปของบอท
class _HeldLine extends StatelessWidget {
  const _HeldLine({required this.polling, required this.onRefresh});

  final bool polling;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: JuntraColors.cyan.withValues(alpha: 0.18)),
        ),
      ),
      child: Row(
        children: [
          if (polling)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: JuntraColors.cyan,
              ),
            )
          else
            const Icon(Icons.support_agent, size: 15, color: JuntraColors.cyan),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'ส่งถึงเจ้าหน้าที่แล้วค่ะ · รอคำตอบสักครู่นะคะ',
              style: TextStyle(fontSize: 12, color: JuntraColors.textMuted),
            ),
          ),
          TextButton(
            onPressed: onRefresh,
            style: TextButton.styleFrom(
              foregroundColor: JuntraColors.cyan,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle: const TextStyle(fontSize: 11.5),
            ),
            child: const Text('ดูคำตอบล่าสุด'),
          ),
        ],
      ),
    );
  }
}

/// หมดเวลาถามต่อ — ข้อความของเซิร์ฟเวอร์ + ทางไปต่อสองทาง (เว็บ "การ์ดปิดท้าย")
class _QaOverPanel extends StatelessWidget {
  const _QaOverPanel({
    required this.message,
    required this.roomShort,
    required this.onPackages,
    required this.onFresh,
  });

  final String message;
  final String roomShort;
  final VoidCallback onPackages;
  final VoidCallback onFresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: JuntraColors.gold.withValues(alpha: 0.12)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(
              fontSize: 12.5,
              color: JuntraColors.textLavender,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _Chip(
                  icon: '🔮',
                  label: 'เปิดไพ่ชุดใหม่',
                  strong: true,
                  onTap: onPackages,
                ),
                _Chip(
                  icon: '💬',
                  label: 'คุยเรื่องอื่นกับ$roomShort',
                  strong: true,
                  onTap: onFresh,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.msg,
    required this.roomKey,
    required this.roomName,
    required this.imageUrl,
    required this.accent,
    this.offersDisabledReason,
    this.onRetry,
    this.onCopy,
    this.onReport,
    this.onOffer,
    this.voicePlaying = false,
    this.onVoice,
  });

  final _Msg msg;
  final String roomKey;
  final String roomName;
  final String? imageUrl;
  final Color accent;

  /// บิลค้างขวางการเปิดไพ่ — การ์ดแพ็กเกจกดไม่ได้พร้อมคำบอก
  final String? offersDisabledReason;
  final VoidCallback? onRetry;
  final VoidCallback? onCopy;

  /// รายงานข้อความนี้ (Google Play: AI-Generated Content policy)
  final VoidCallback? onReport;
  final void Function(ChatOffer offer, String? question)? onOffer;
  final bool voicePlaying;
  final VoidCallback? onVoice;

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.sizeOf(context).width * 0.78;
    final speaker = !msg.fromUser && !msg.isSystem;

    final Color bg;
    final Color fg;
    Border? border;
    if (msg.isSystem) {
      bg = JuntraColors.goldMid.withValues(alpha: 0.10);
      fg = JuntraColors.textMuted;
      border = Border.all(color: JuntraColors.goldMid.withValues(alpha: 0.45));
    } else if (msg.fromUser) {
      bg = JuntraColors.gold.withValues(alpha: 0.18);
      fg = JuntraColors.textCream;
      border = Border.all(color: JuntraColors.gold.withValues(alpha: 0.4));
    } else if (msg.staff) {
      // เจ้าหน้าที่ — ต้องดูต่างจากผู้พยากรณ์ชัดเจน ลูกค้าจะได้รู้ว่าคนจริงตอบ
      bg = JuntraColors.cyan.withValues(alpha: 0.08);
      fg = JuntraColors.textPrimary;
      border = Border.all(color: JuntraColors.cyan.withValues(alpha: 0.45));
    } else {
      bg = JuntraColors.bgPurpleDeep.withValues(alpha: 0.7);
      fg = JuntraColors.textLavender;
      border = Border.all(color: accent.withValues(alpha: 0.18));
    }

    final indent = speaker ? 34.0 : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: msg.fromUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (speaker)
            Padding(
              padding: const EdgeInsets.only(left: 36, bottom: 2),
              child: msg.staff
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.verified_user_outlined,
                          size: 11,
                          color: JuntraColors.cyan,
                        ),
                        SizedBox(width: 3),
                        Text(
                          'เจ้าหน้าที่',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: JuntraColors.cyan,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      roomName,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: accent.withValues(alpha: 0.9),
                      ),
                    ),
            ),
          Row(
            mainAxisAlignment: msg.fromUser
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (speaker) ...[
                msg.staff
                    ? Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: JuntraColors.cyan.withValues(alpha: 0.14),
                          border: Border.all(
                            color: JuntraColors.cyan.withValues(alpha: 0.6),
                          ),
                        ),
                        child: const Icon(
                          Icons.support_agent,
                          size: 16,
                          color: JuntraColors.cyan,
                        ),
                      )
                    : RoomAvatar(
                        roomKey: roomKey,
                        imageUrl: imageUrl,
                        size: 28,
                        accent: accent,
                        ring: false,
                      ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  constraints: BoxConstraints(maxWidth: maxW),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(14),
                      topRight: const Radius.circular(14),
                      bottomLeft: Radius.circular(msg.fromUser ? 14 : 4),
                      bottomRight: Radius.circular(msg.fromUser ? 4 : 14),
                    ),
                    border: border,
                  ),
                  // คำตอบของผู้พยากรณ์ใช้ **ตัวหนา** และ bullet เป็นปกติ
                  child: msg.fromUser || msg.isSystem
                      ? Text(
                          msg.text,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: fg,
                            height: 1.55,
                          ),
                        )
                      : MarkdownBody(
                          data: msg.text,
                          selectable: true,
                          styleSheet: _markdownStyle(fg),
                        ),
                ),
              ),
            ],
          ),
          if (msg.note != null)
            Padding(
              padding: EdgeInsets.only(
                top: 3,
                right: msg.fromUser ? 4 : 0,
                left: indent,
              ),
              child: Text(
                msg.note!,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: JuntraColors.textFaint,
                ),
              ),
            ),
          if (msg.offers.isNotEmpty && onOffer != null)
            Padding(
              padding: const EdgeInsets.only(left: 34, top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final o in msg.offers)
                    _OfferCard(
                      offer: o,
                      disabledReason: o.locked
                          ? 'เปิดได้อีก ${o.lockedUntil}'
                          : offersDisabledReason,
                      onTap: () => onOffer!(o, msg.question),
                    ),
                ],
              ),
            ),
          if (onRetry != null ||
              onCopy != null ||
              onReport != null ||
              onVoice != null)
            Padding(
              padding: EdgeInsets.only(
                top: 2,
                left: indent,
                right: msg.fromUser ? 2 : 0,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onVoice != null)
                    TextButton.icon(
                      onPressed: onVoice,
                      icon: Icon(
                        voicePlaying
                            ? Icons.stop_circle_outlined
                            : Icons.volume_up_rounded,
                        size: 15,
                      ),
                      label: Text(
                        voicePlaying ? 'หยุดเสียง' : 'ฟังเสียง',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: JuntraColors.gold,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  if (onRetry != null)
                    TextButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh, size: 14),
                      label: const Text(
                        'ลองส่งใหม่',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: JuntraColors.gold,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  if (onCopy != null)
                    IconButton(
                      onPressed: onCopy,
                      icon: const Icon(Icons.copy_rounded, size: 14),
                      color: JuntraColors.textFaint,
                      tooltip: 'คัดลอก',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 26,
                      ),
                    ),
                  if (onReport != null)
                    IconButton(
                      onPressed: onReport,
                      icon: const Icon(Icons.flag_outlined, size: 14),
                      color: JuntraColors.textFaint,
                      tooltip: 'รายงานข้อความนี้',
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 26,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.2);
  }

  MarkdownStyleSheet _markdownStyle(Color fg) => MarkdownStyleSheet(
    p: TextStyle(fontSize: 13.5, color: fg, height: 1.55),
    strong: const TextStyle(
      fontWeight: FontWeight.w700,
      color: JuntraColors.textCream,
    ),
    em: const TextStyle(
      fontStyle: FontStyle.italic,
      color: JuntraColors.purpleBright,
    ),
    listBullet: TextStyle(fontSize: 13.5, color: fg),
    h1: baiJamjuree(size: 17, color: JuntraColors.gold),
    h2: baiJamjuree(size: 15.5, color: JuntraColors.gold),
    h3: baiJamjuree(size: 14.5, color: JuntraColors.gold),
    blockquote: TextStyle(fontSize: 13, color: fg.withValues(alpha: 0.8)),
    code: const TextStyle(fontSize: 12.5, color: JuntraColors.textCream),
    blockSpacing: 7,
  );
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble({
    required this.roomKey,
    required this.imageUrl,
    required this.accent,
  });

  final String roomKey;
  final String? imageUrl;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          RoomAvatar(
            roomKey: roomKey,
            imageUrl: imageUrl,
            size: 28,
            accent: accent,
            ring: false,
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: JuntraColors.bgPurpleDeep.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child:
                      Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: JuntraColors.gold.withValues(alpha: 0.8),
                              shape: BoxShape.circle,
                            ),
                          )
                          .animate(onPlay: (c) => c.repeat())
                          .fadeOut(duration: 600.ms, delay: (i * 200).ms)
                          .then()
                          .fadeIn(duration: 400.ms),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

/// แถบปุ่มคำถามลัด — ตรรกะเดียวกับเว็บ
///
///  1. คุยต่อไม่ได้ → ปุ่มทางออกที่กดได้จริงเสมอ (ไม่ใช่ปุ่มตาย)
///  2. ผู้พยากรณ์กำลังถามกลับ → ถ้ามีตัวเลือกคำตอบที่ผู้พยากรณ์คิดให้ (`ai_suggestions`) กดตอบได้เลย
///     ไม่มี = ยุบเหลือปุ่มเดียว เพราะถ้าผู้ใช้กดคำถามทั่วไปตอนนี้ บอทจะตีความเป็นคำตอบของ
///     คำถามที่ค้างอยู่ แล้วโฟลว์ทำนายพัง
///  3. ปกติ → ปุ่มจากผู้พยากรณ์ (ถ้ามี) แทนชุดตายตัว + หมวดคำถาม
class _SuggestionStrip extends ConsumerWidget {
  const _SuggestionStrip({
    required this.selfName,
    required this.suggestions,
    required this.aiSuggestions,
    required this.awaiting,
    required this.open,
    required this.blocked,
    required this.blockedReason,
    required this.busy,
    required this.onOpen,
    required this.onPick,
    required this.onTopics,
    required this.onTopUp,
  });

  final String selfName;
  final List<ChatSuggestion> suggestions;
  final List<String> aiSuggestions;
  final bool awaiting;
  final bool open;
  final bool blocked;
  final String blockedReason;
  final bool busy;
  final VoidCallback onOpen;
  final ValueChanged<String> onPick;
  final VoidCallback onTopics;
  final VoidCallback onTopUp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ปุ่มทางออกไปบริการอื่น — เฉพาะที่หลังบ้านยังเปิดขาย (ปิดแล้วกดไปก็เจอหน้าปิดปรับปรุง)
    final cfg = ref.watch(appConfigValueProvider);
    if (blocked) {
      return _wrap(
        context,
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              // เติมเครดิตจบในแชทเหมือนเว็บ ไม่พาลูกค้าออกไปหน้าอื่นแล้วหลงทาง
              _Chip(
                icon: '💳',
                label: 'เติมเครดิตที่นี่',
                strong: true,
                onTap: onTopUp,
              ),
              const _ExitChip(
                icon: '🔮',
                label: 'เปิดไพ่ยิปซี',
                route: Routes.spreads,
                strong: true,
              ),
              if (cfg.isOpen('deep'))
                const _ExitChip(
                  icon: '🌟',
                  label: 'ดูดวงเชิงลึก',
                  route: Routes.deep,
                  strong: true,
                ),
              if (cfg.isOpen('horoscope'))
                const _ExitChip(
                  icon: '🌙',
                  label: 'ดวงรายวัน',
                  route: Routes.horoscope,
                ),
              if (cfg.isOpen('numerology'))
                const _ExitChip(
                  icon: '🔢',
                  label: 'เลขศาสตร์',
                  route: Routes.numerology,
                ),
              if (cfg.isOpen('auspicious'))
                const _ExitChip(
                  icon: '📿',
                  label: 'ฤกษ์ยาม',
                  route: Routes.auspicious,
                ),
            ],
          ),
        ),
        label: blockedReason.isEmpty ? 'ลองทางนี้ต่อได้เลยค่ะ' : blockedReason,
      );
    }

    if (awaiting && !open) {
      if (aiSuggestions.isNotEmpty) {
        return _wrap(
          context,
          _row([
            for (final q in aiSuggestions)
              _Chip(label: q, ai: true, onTap: busy ? null : () => onPick(q)),
          ]),
          label: '💬 ตอบ$selfNameได้เลย หรือพิมพ์เองก็ได้ค่ะ',
        );
      }
      if (suggestions.isEmpty) return const SizedBox.shrink();
      return _wrap(
        context,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '💬 $selfNameกำลังรอคำตอบของคุณอยู่ค่ะ',
                  style: const TextStyle(
                    fontSize: 12,
                    color: JuntraColors.textMuted,
                  ),
                ),
              ),
              _Chip(label: 'ดูคำถามแนะนำ', onTap: onOpen),
            ],
          ),
        ),
      );
    }

    // ระหว่างผู้พยากรณ์พิมพ์ ชิปยังอยู่ที่เดิมแต่กดไม่ได้ (จางลง)
    // เลย์เอาต์จึงไม่กระโดดและผู้ใช้ไม่งงว่าปุ่มหายไปไหน
    final chips = aiSuggestions.isNotEmpty
        ? [
            for (final q in aiSuggestions)
              _Chip(
                icon: '✨',
                label: q,
                ai: true,
                onTap: busy ? null : () => onPick(q),
              ),
          ]
        : [
            for (final s in suggestions)
              _Chip(
                icon: s.icon,
                label: s.label,
                onTap: busy ? null : () => onPick(s.prompt),
              ),
          ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return _wrap(
      context,
      _row([
        ...chips,
        // ปุ่มกางหมวดคำถาม 24 ข้อ — ชุดเดียวกับที่เว็บกางในแชท
        _Chip(icon: '⋯', label: 'หมวดคำถาม', onTap: busy ? null : onTopics),
      ]),
      label: aiSuggestions.isNotEmpty ? '✨ ถามต่อจากเรื่องนี้' : null,
    );
  }

  Widget _row(List<Widget> children) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(children: children),
  );

  Widget _wrap(BuildContext context, Widget child, {String? label}) {
    return Container(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: JuntraColors.gold.withValues(alpha: 0.10)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: JuntraColors.textFaint,
                ),
              ),
            ),
          child,
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    this.icon,
    required this.label,
    this.onTap,
    this.strong = false,
    this.ai = false,
  });

  final String? icon;
  final String label;
  final VoidCallback? onTap;
  final bool strong;

  /// ปุ่มที่ผู้พยากรณ์คิดมาให้ (ขอบม่วงแบบ `.chip-ai` ของเว็บ)
  final bool ai;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final edge = ai ? JuntraColors.purpleBright : JuntraColors.gold;
    return Opacity(
      opacity: disabled ? 0.42 : 1,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: edge.withValues(alpha: strong ? 0.22 : 0.09),
          borderRadius: BorderRadius.circular(JuntraRadius.chip),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(JuntraRadius.chip),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.8,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(JuntraRadius.chip),
                border: Border.all(
                  color: edge.withValues(alpha: strong ? 0.65 : 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Text(icon!, style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: strong
                            ? JuntraColors.textCream
                            : JuntraColors.textLavender,
                        fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
                      ),
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

class _ExitChip extends StatelessWidget {
  const _ExitChip({
    required this.icon,
    required this.label,
    required this.route,
    this.strong = false,
  });

  final String icon;
  final String label;
  final String route;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return _Chip(
      icon: icon,
      label: label,
      strong: strong,
      onTap: () => context.pushOnce(route),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.onSend,
    required this.hint,
    required this.onMic,
    this.enabled = true,
    this.lockedReason,
    this.showMic = false,
    this.listening = false,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final String hint;
  final bool enabled;

  /// พิมพ์ไม่ได้เพราะอะไร (ครบโควตา · เครดิตหมด · หมดเวลาถามต่อ) — null = พิมพ์ได้ตามปกติ
  final String? lockedReason;
  final bool showMic;
  final bool listening;
  final VoidCallback onMic;

  @override
  Widget build(BuildContext context) {
    final locked = lockedReason != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      decoration: BoxDecoration(
        color: JuntraColors.bgDeepest.withValues(alpha: 0.85),
        border: Border(
          top: BorderSide(color: JuntraColors.gold.withValues(alpha: 0.2)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                // ไมค์กำลังฟัง = ช่องพิมพ์ยังเปิดอยู่ ลูกค้าเห็นข้อความที่ได้ทันที
                enabled: !locked,
                style: const TextStyle(
                  color: JuntraColors.textCream,
                  fontSize: 14,
                ),
                cursorColor: JuntraColors.gold,
                minLines: 1,
                maxLines: 4,
                maxLength: 2000,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => enabled ? onSend() : null,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: locked
                      ? lockedReason
                      : (listening ? 'กำลังฟังอยู่ค่ะ… พูดได้เลย' : hint),
                  hintStyle: const TextStyle(
                    color: JuntraColors.textFaint,
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: JuntraColors.bgPurpleDeep.withValues(alpha: 0.6),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: JuntraColors.line),
                  ),
                ),
              ),
            ),
            if (showMic && !locked) ...[
              const SizedBox(width: 6),
              IconButton(
                onPressed: onMic,
                tooltip: listening ? 'หยุดฟัง' : 'พูดแทนพิมพ์',
                icon: Icon(
                  listening ? Icons.stop_rounded : Icons.mic_none_rounded,
                ),
                color: listening ? JuntraColors.rose : JuntraColors.goldLight,
                style: IconButton.styleFrom(
                  backgroundColor: listening
                      ? JuntraColors.rose.withValues(alpha: 0.16)
                      : JuntraColors.bgPurpleDeep.withValues(alpha: 0.6),
                  fixedSize: const Size(44, 44),
                ),
              ),
            ],
            const SizedBox(width: 8),
            // ปุ่มที่กดไม่ได้ต้อง "ดูกดไม่ได้" ชัดเจน ไม่ใช่ทองเต็มใบเหมือนกดได้
            Opacity(
              opacity: enabled ? 1.0 : 0.4,
              child: InkWell(
                onTap: enabled ? onSend : null,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: enabled ? JuntraColors.goldButtonGradient : null,
                    color: enabled ? null : JuntraColors.bgPurple,
                  ),
                  child: Icon(
                    locked ? Icons.lock_outline : Icons.send_rounded,
                    color: enabled
                        ? JuntraColors.bgPurpleDeep
                        : JuntraColors.textFaint,
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({
    required this.offer,
    required this.onTap,
    this.disabledReason,
  });

  final ChatOffer offer;
  final VoidCallback onTap;

  /// กดไม่ได้เพราะอะไร (ข้อห้ามเปิดซ้ำ / บิลค้าง) — null = กดได้
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final price = offer.price;
    final disabled = disabledReason != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Opacity(
        opacity: disabled ? 0.55 : 1,
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.74,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              gradient: JuntraColors.purpleCardGradient,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: JuntraColors.gold.withValues(
                  alpha: disabled ? 0.2 : 0.45,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  disabled ? Icons.lock_clock_outlined : Icons.style_outlined,
                  color: JuntraColors.gold,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        offer.label,
                        style: const TextStyle(
                          fontSize: 13,
                          color: JuntraColors.textCream,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (disabledReason != null)
                        Text(
                          disabledReason!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: JuntraColors.goldMid,
                            height: 1.4,
                          ),
                        )
                      else if (offer.blurb != null && offer.blurb!.isNotEmpty)
                        Text(
                          offer.blurb!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: JuntraColors.textMuted,
                            height: 1.4,
                          ),
                        ),
                    ],
                  ),
                ),
                if (price != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    price <= 0 ? 'ฟรี' : formatCredits(price),
                    style: const TextStyle(
                      fontSize: 12,
                      color: JuntraColors.gold,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (!disabled)
                  const Icon(
                    Icons.chevron_right,
                    color: JuntraColors.gold,
                    size: 18,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
