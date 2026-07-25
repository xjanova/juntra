import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/chat_repository.dart';
import '../../core/auth/auth_state.dart';
import '../../shared/widgets/juntra_tab_bar.dart';
import '../../shared/widgets/starry_background.dart';

/// Screen 7 — Mae Mor AI chat.
///
/// Wired to `POST /v1/chat/conversations` (start) and
/// `/v1/chat/conversations/{id}/send`, which proxy to the Thaiprompt
/// Fortune Bot pool with a local AiOracle fallback. The system prompt
/// (server-side) makes the model answer in Mae Mor's voice.
///
/// ความสอดคล้องกับเว็บ (จันทรา.online/chat) — ต้องเท่ากันทุกอย่าง:
///   - ปุ่มคำถามลัดชุดเดียวกัน (backend ส่ง `suggestions` มาจาก
///     App\Support\ChatSuggestions ซึ่งเป็นแหล่งข้อมูลกลางของทั้งสองฝั่ง)
///   - ยุบแถบปุ่มเมื่อแม่หมอกำลังถามกลับ (`awaiting`) เพื่อไม่ให้ผู้ใช้กด
///     คำถามทั่วไปแล้วบทสนทนาหลุดโฟลว์ทำนาย
///   - ป้ายโควตาคุยฟรีรายวัน / เครดิต
///   - render markdown (คำตอบใช้ **ตัวหนา** และ bullet เป็นปกติ)
///   - แยกเคส 402 / 429 daily_limit / 429 rate-limit / 409 ให้คนละข้อความ
///
/// Two entry modes:
///   - `/chat`        → คุยต่อจากบทสนทนาล่าสุด (สร้างใหม่เมื่อยังไม่มี)
///   - `/chat?id=N`   → resume บทสนทนาที่ระบุ
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, this.resumeConversationId});

  /// If provided, load that conversation instead of the most recent one.
  final int? resumeConversationId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_Msg>[];

  bool _typing = false;
  bool _starting = true;
  int? _conversationId;

  // สถานะโควตา/ปุ่มลัด — ซิงก์จากทุก response ของ backend ไม่เดาเอง
  List<_Suggestion> _suggestions = const [];
  bool _awaiting = false;        // แม่หมอกำลังรอคำตอบอยู่
  bool _suggestOpen = false;     // ผู้ใช้กดกางปุ่มลัดตอน awaiting
  bool _blocked = false;         // คุยต่อไม่ได้ (ครบโควตา / เครดิตหมด)
  String _blockedReason = '';
  int _dailyLimit = 0;
  int _dailyLeft = 0;
  double _cost = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /* ══════════════════════ session ══════════════════════ */

  Future<void> _bootstrap() async {
    final auth = ref.read(authControllerProvider);

    // AuthUnknown = ยังโหลด session ไม่เสร็จ ต้องรอ ไม่ใช่ปล่อยผ่านไปยิง API
    // แล้วไปเจอ 401 (ของเดิมเช็คเฉพาะ AuthGuest ผู้ใช้ที่เพิ่งเปิดแอพจึงเห็น
    // "session หมดอายุ" ทั้งที่ล็อกอินอยู่)
    if (auth is AuthUnknown) {
      await ref.read(authControllerProvider.notifier).refresh();
    }

    if (!mounted) return;
    if (ref.read(authControllerProvider) is! AuthAuthenticated) {
      setState(() => _starting = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(Routes.login);
      });
      return;
    }

    final resumeId = widget.resumeConversationId;
    if (resumeId != null) {
      await _resumeSession(resumeId);
    } else {
      await _openLatestOrStart();
    }
  }

  /// เปิดบทสนทนาล่าสุดต่อ ถ้ายังไม่มีค่อยสร้างใหม่
  ///
  /// ของเดิมยิง POST /conversations ทุกครั้งที่แตะแท็บ "แม่หมอ" → ห้องเปล่า
  /// งอกบนเซิร์ฟเวอร์ทุกครั้ง (เสียค่าเรียก upstream ขอคำทักทายด้วย) และผู้ใช้
  /// เสียบริบทที่คุยค้างไว้ ต่างจากเว็บที่คุยต่อห้องเดิมเสมอ
  Future<void> _openLatestOrStart() async {
    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      final list = await repo.listConversations();
      if (!mounted) return;

      if (list.isNotEmpty) {
        final id = (list.first['id'] as num?)?.toInt();
        if (id != null) {
          await _resumeSession(id);
          return;
        }
      }
    } catch (_) {
      // ดึงรายการไม่ได้ → ตกไปสร้างห้องใหม่ตามเดิม
    }
    await _startSession();
  }

  Future<void> _startSession() async {
    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      final res = await repo.startConversation();
      if (!mounted) return;

      final convo = (res['conversation'] as Map?) ?? const {};
      _conversationId = (convo['id'] as num?)?.toInt();
      setState(() {
        _messages
          ..clear()
          ..addAll(_parseMessages(convo['messages']));
        if (_messages.isEmpty) {
          _messages.add(_Msg.bot('สวัสดีค่ะลูก แม่หมอจันทราอยู่ตรงนี้แล้ว · '
              'อยากปรึกษาเรื่องอะไรเป็นพิเศษวันนี้คะ?'));
        }
        _applyState(res);
        _starting = false;
      });
      _scrollToEnd();
      ref.invalidate(chatConversationsProvider);
    } catch (_) {
      // เน็ตล่ม → ยังเปิดหน้าจอให้ใช้ได้พร้อมคำทักทายในเครื่อง
      if (!mounted) return;
      setState(() {
        _messages.add(_Msg.bot('สวัสดีค่ะลูก แม่หมอจันทราอยู่ตรงนี้แล้ว · '
            'อยากปรึกษาเรื่องอะไรเป็นพิเศษวันนี้คะ?'));
        _starting = false;
      });
    }
  }

  Future<void> _resumeSession(int id) async {
    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      final convo = await repo.getConversation(id);
      if (!mounted) return;

      _conversationId = (convo['id'] as num?)?.toInt() ?? id;
      setState(() {
        _messages
          ..clear()
          ..addAll(_parseMessages(convo['messages']));
        if (_messages.isEmpty) {
          _messages.add(_Msg.bot('แม่หมอกลับมาอยู่ตรงนี้แล้วค่ะ · พิมพ์ต่อได้เลย'));
        }
        _applyState(convo);
        _starting = false;
      });
      _scrollToEnd();
    } catch (e) {
      // อย่าสร้างห้องใหม่เงียบ ๆ — ผู้ใช้จะเสียที่ค้างไว้และได้ห้องเปล่าเพิ่ม
      if (kDebugMode) debugPrint('[Chat] resume failed: $e');
      if (!mounted) return;
      setState(() {
        _messages.add(_Msg.system(
            'แม่หมอเปิดบทสนทนาเก่าไม่ได้ค่ะ · กดย้อนกลับแล้วลองอีกครั้งได้นะคะ'));
        _starting = false;
      });
    }
  }

  List<_Msg> _parseMessages(dynamic raw) {
    final list = (raw as List?) ?? const [];
    return list.cast<Map>().map((m) {
      final text = m['content']?.toString() ?? '';
      return m['role'] == 'assistant' ? _Msg.bot(text) : _Msg.user(text);
    }).toList();
  }

  /// ซิงก์โควตา/ปุ่มลัด/สถานะจาก response ของ backend
  void _applyState(Map<String, dynamic> data) {
    final limit = (data['daily_limit'] as num?)?.toInt();
    final left = (data['daily_left'] as num?)?.toInt();
    final cost = (data['cost'] as num?)?.toDouble();
    if (limit != null) _dailyLimit = limit;
    if (left != null) _dailyLeft = left;
    if (cost != null) _cost = cost;

    if (data['awaiting'] is bool) _awaiting = data['awaiting'] as bool;

    final sugg = data['suggestions'];
    if (sugg is List && sugg.isNotEmpty) {
      _suggestions = sugg
          .whereType<Map>()
          .map(_Suggestion.fromJson)
          .where((s) => s.label.isNotEmpty && s.prompt.isNotEmpty)
          .toList();
    }

    if (_dailyLimit > 0 && _dailyLeft <= 0) {
      _blocked = true;
      _blockedReason = 'วันนี้คุยครบแล้ว — พรุ่งนี้แม่หมอรอฟังต่อนะคะ';
    }
  }

  /* ══════════════════════ ส่งข้อความ ══════════════════════ */

  String _newIdempotencyKey() {
    final r = math.Random();
    return '${DateTime.now().microsecondsSinceEpoch}-'
        '${List.generate(4, (_) => r.nextInt(36).toRadixString(36)).join()}';
  }

  Future<void> _send({String? overrideText, String? reuseIdem, _Msg? replacing}) async {
    final text = (overrideText ?? _controller.text).trim();
    if (text.isEmpty || _typing || _blocked) return;

    // คีย์เดิมเมื่อ "ลองใหม่" ข้อความเดิม → backend กันการตัดเงินซ้ำได้จริง
    // (จำเป็นมากเพราะ dio retry POST อัตโนมัติเมื่อ timeout/5xx)
    final idem = reuseIdem ?? _newIdempotencyKey();

    // วงเล็บชัด ๆ ว่า cascade ทำงานกับผลของ ?? (ตัวเดิมตอน retry / ตัวใหม่ตอนส่งครั้งแรก)
    final mine = (replacing ?? _Msg.user(text))
      ..idempotencyKey = idem
      ..failed = false;

    setState(() {
      if (replacing == null) _messages.add(mine);
      _typing = true;
    });
    if (overrideText == null) _controller.clear();
    _scrollToEnd();

    try {
      if (_conversationId == null) await _startSession();
      if (_conversationId == null) throw StateError('no conversation');

      final repo = await ref.read(chatRepositoryProvider.future);
      final res = await repo.send(
        conversationId: _conversationId!,
        text: text,
        idempotencyKey: idem,
      );
      if (!mounted) return;

      setState(() {
        _typing = false;
        _suggestOpen = false;
        _applyState(res);
        _messages.add(_Msg.bot(res['reply']?.toString().trim() ?? _gracefulFallback()));
      });
      _scrollToEnd();
      ref.invalidate(chatConversationsProvider);
      if (res['balance'] is num) {
        ref.read(authControllerProvider.notifier).refresh();
      }
      return;
    } on ApiException catch (e) {
      if (!mounted) return;
      await _handleSendError(e, mine);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _typing = false;
        mine.failed = true;
        _messages.add(_Msg.system(
            'เครือข่ายมีปัญหาค่ะ — กด "ลองส่งใหม่" ได้เลย ข้อความจะไม่ถูกส่งซ้ำซ้อน'));
      });
      _scrollToEnd();
    }
  }

  Future<void> _handleSendError(ApiException e, _Msg mine) async {
    switch (e.statusCode) {
      case 402: // เครดิตไม่พอ
        setState(() {
          _typing = false;
          _blocked = true;
          _blockedReason = 'เครดิตไม่พอ — เติมเงินแล้วคุยต่อได้เลยค่ะ';
          _messages.add(_Msg.system(e.message));
        });
        _scrollToEnd();
        await _showTopUpSheet(e.message);
        return;

      case 429:
        if (e.reasonCode == 'daily_limit') {
          // ครบโควตาคุยฟรีวันนี้ — ไม่ใช่ error ของผู้ใช้ ชวนไปทางอื่นต่อ
          setState(() {
            _typing = false;
            _dailyLeft = 0;
            _blocked = true;
            _blockedReason = 'วันนี้คุยครบแล้ว — พรุ่งนี้แม่หมอรอฟังต่อนะคะ';
            _messages.add(_Msg.system(e.message));
          });
        } else {
          setState(() {
            _typing = false;
            mine.failed = true;
            _messages.add(_Msg.system(
                'พิมพ์เร็วเกินไปนะคะลูก — รอสักครู่แล้วกด "ลองส่งใหม่" ได้เลย'));
          });
        }
        _scrollToEnd();
        return;

      case 409: // ข้อความเดิมกำลังส่งอยู่ (idempotency guard) — คำตอบอยู่ที่เซิร์ฟเวอร์
        setState(() => _typing = false);
        await _syncFromServer();
        return;

      case 401:
        setState(() {
          _typing = false;
          mine.failed = true;
          _messages.add(_Msg.system('session หมดอายุค่ะ — กรุณาเข้าสู่ระบบใหม่'));
        });
        _scrollToEnd();
        return;

      default:
        setState(() {
          _typing = false;
          mine.failed = true;
          _messages.add(_Msg.system(e.message));
        });
        _scrollToEnd();
    }
  }

  /// ดึงบทสนทนาจากเซิร์ฟเวอร์มาทับ — ใช้ตอนเจอ 409 ซึ่งแปลว่าข้อความถูกส่ง
  /// ไปแล้วจริง คำตอบจึงอยู่ฝั่งเซิร์ฟเวอร์ ไม่ควรให้ผู้ใช้กดส่งซ้ำ
  Future<void> _syncFromServer() async {
    final id = _conversationId;
    if (id == null) return;
    try {
      final repo = await ref.read(chatRepositoryProvider.future);
      final convo = await repo.getConversation(id);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(_parseMessages(convo['messages']));
        _applyState(convo);
      });
      _scrollToEnd();
    } catch (_) {
      if (!mounted) return;
      setState(() => _messages.add(_Msg.system(
          'ข้อความก่อนหน้ากำลังส่งอยู่ค่ะ รอสักครู่แล้วดึงหน้าลงเพื่อรีเฟรชนะคะ')));
    }
  }

  Future<void> _showTopUpSheet(String message) async {
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
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: JuntraColors.gold.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text('เครดิตไม่พอ', style: baiJamjuree(size: 18, color: JuntraColors.gold)),
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
                    await context.push(Routes.wallet);
                    // กลับจากหน้าเติมเงินแล้วต้องพิมพ์ต่อได้ทันที
                    // (ถ้าเครดิตยังไม่พอจริง เซิร์ฟเวอร์จะตอบ 402 ให้เองอีกครั้ง)
                    // เดิม _blocked ถูกตั้ง true แล้วไม่มีทางกลับเป็น false
                    // ตลอดอายุหน้าจอ = เติมเงินเสร็จก็ยังคุยไม่ได้จนกว่าจะปิดแอพ
                    if (mounted) {
                      setState(() {
                        _blocked = false;
                        _blockedReason = '';
                      });
                    }
                  },
                  child: const Text('ไปหน้าเติมเครดิต',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.of(sheetCtx).pop(),
                child: const Text('ปิด',
                    style: TextStyle(color: JuntraColors.textFaint)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,   // เดิมบวก 80 = overscroll glow ทุกครั้ง
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  String _gracefulFallback() =>
      'แม่หมอกำลังพักสายตาซักครู่นะลูก... ลองส่งข้อความใหม่อีกครั้งในอีกสักพักนะคะ ✨';

  /* ══════════════════════ build ══════════════════════ */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const JuntraTabBar(currentIndex: 2),
      body: Stack(
        children: [
          const StarryBackground(density: 30, intensity: 0.4),
          SafeArea(
            child: Column(
              children: [
                _ChatHeader(
                  typing: _typing,
                  onNewChat: _starting ? null : _confirmNewChat,
                ),
                if (_starting)
                  const LinearProgressIndicator(
                    minHeight: 1.5,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(JuntraColors.gold),
                  ),
                if (_dailyLimit > 0 || _cost > 0)
                  _QuotaBar(dailyLimit: _dailyLimit, dailyLeft: _dailyLeft, cost: _cost),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    itemCount: _messages.length + (_typing ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (_typing && i == _messages.length) {
                        return const _TypingBubble();
                      }
                      final m = _messages[i];
                      return _Bubble(
                        msg: m,
                        onRetry: m.failed
                            ? () => _send(
                                  overrideText: m.text,
                                  reuseIdem: m.idempotencyKey,
                                  replacing: m,
                                )
                            : null,
                        onCopy: m.fromUser || m.isSystem ? null : () => _copy(m.text),
                      );
                    },
                  ),
                ),
                _SuggestionStrip(
                  suggestions: _suggestions,
                  awaiting: _awaiting,
                  open: _suggestOpen,
                  blocked: _blocked,
                  blockedReason: _blockedReason,
                  busy: _typing,
                  onOpen: () => setState(() => _suggestOpen = true),
                  onPick: (prompt) => _send(overrideText: prompt),
                ),
                _InputBar(
                  controller: _controller,
                  onSend: _send,
                  enabled: !_typing && !_blocked,
                  blockedReason: _blocked ? _blockedReason : null,
                ),
              ],
            ),
          ),
        ],
      ),
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JuntraColors.bgPurpleDeep,
        title: Text('เริ่มบทสนทนาใหม่?', style: baiJamjuree(size: 17, color: JuntraColors.gold)),
        content: const Text(
          'บทสนทนาปัจจุบันจะถูกเก็บไว้ในประวัติ เปิดกลับมาอ่านได้ตลอดค่ะ',
          style: TextStyle(color: JuntraColors.textLavender, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก', style: TextStyle(color: JuntraColors.textFaint)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('เริ่มใหม่', style: TextStyle(color: JuntraColors.gold)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _starting = true;
      _conversationId = null;
      _blocked = _dailyLimit > 0 && _dailyLeft <= 0;
      _awaiting = false;
      _suggestOpen = false;
      _messages.clear();
    });
    await _startSession();
  }
}

/* ══════════════════════ models ══════════════════════ */

class _Msg {
  _Msg({required this.text, required this.fromUser, this.isSystem = false});

  final String text;
  final bool fromUser;

  /// ข้อความจาก "ระบบ" (โควตาหมด / เน็ตล่ม) — ต้องหน้าตาไม่เหมือนคำพูดแม่หมอ
  /// ไม่งั้นผู้ใช้เข้าใจว่าแม่หมอพูดเรื่องระบบเอง
  final bool isSystem;

  bool failed = false;
  String? idempotencyKey;

  factory _Msg.user(String t) => _Msg(text: t, fromUser: true);
  factory _Msg.bot(String t) => _Msg(text: t, fromUser: false);
  factory _Msg.system(String t) => _Msg(text: t, fromUser: false, isSystem: true);
}

class _Suggestion {
  const _Suggestion({required this.label, required this.prompt, required this.icon});

  final String label;
  final String prompt;
  final String icon;

  factory _Suggestion.fromJson(Map<dynamic, dynamic> j) => _Suggestion(
        label: j['label']?.toString() ?? '',
        prompt: j['prompt']?.toString() ?? '',
        icon: j['icon']?.toString() ?? '✨',
      );
}

/* ══════════════════════ widgets ══════════════════════ */

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.typing, this.onNewChat});

  final bool typing;
  final VoidCallback? onNewChat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 12),
      decoration: BoxDecoration(
        color: JuntraColors.bgDeepest.withValues(alpha: 0.4),
        border: Border(bottom: BorderSide(
          color: JuntraColors.gold.withValues(alpha: 0.2),
        )),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: JuntraColors.gold, size: 28),
            tooltip: 'ย้อนกลับ',
            onPressed: () => context.canPop() ? context.pop() : context.go(Routes.home),
          ),
          const _MorAvatar(size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('แม่หมอจันทรา', style: baiJamjuree(size: 16)),
                Row(
                  children: [
                    Container(
                      width: 7, height: 7,
                      decoration: const BoxDecoration(
                        color: JuntraColors.mintGreen, shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      typing ? 'กำลังเพ่งไพ่ให้ลูกอยู่...' : 'พร้อมรับฟังลูกอยู่ค่ะ',
                      style: const TextStyle(fontSize: 10, color: JuntraColors.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_comment_outlined, color: JuntraColors.textMuted, size: 20),
            tooltip: 'เริ่มบทสนทนาใหม่',
            onPressed: onNewChat,
          ),
          IconButton(
            icon: const Icon(Icons.history, color: JuntraColors.textMuted),
            tooltip: 'บทสนทนาเก่า',
            onPressed: () => context.push(Routes.chatConversations),
          ),
        ],
      ),
    );
  }
}

/// รูปแม่หมอ — ไฟล์ต้นฉบับ 1536×2752 (~6.7MB) ถ้าไม่ใส่ cacheWidth
/// Flutter จะ decode เต็มความละเอียดลง RAM ทุกครั้งที่วาดอวตาร 28–40px
class _MorAvatar extends StatelessWidget {
  const _MorAvatar({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final px = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipOval(
      child: Image.asset(
        'assets/images/maehmor.png',
        width: size, height: size, fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        cacheWidth: px,
        errorBuilder: (_, _, _) => Container(
          width: size, height: size,
          color: JuntraColors.bgPurple,
          alignment: Alignment.center,
          child: Text('🔮', style: TextStyle(fontSize: size * 0.5)),
        ),
      ),
    );
  }
}

/// ป้ายโควตาคุยฟรี / เครดิต — ให้ตรงกับแถบเดียวกันบนเว็บ
class _QuotaBar extends StatelessWidget {
  const _QuotaBar({required this.dailyLimit, required this.dailyLeft, required this.cost});

  final int dailyLimit;
  final int dailyLeft;
  final double cost;

  @override
  Widget build(BuildContext context) {
    final free = cost <= 0;
    final low = free ? dailyLeft <= 3 : false;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: (low ? JuntraColors.goldMid : JuntraColors.gold).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: JuntraColors.gold.withValues(alpha: low ? 0.5 : 0.2),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(free ? Icons.auto_awesome : Icons.account_balance_wallet_outlined,
              size: 14, color: JuntraColors.gold),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              free
                  ? 'คุยฟรีวันนี้ $dailyLeft / $dailyLimit ข้อความ · รีเซ็ตทุกเที่ยงคืน'
                  : 'หักครั้งละ ฿${cost.toStringAsFixed(cost == cost.roundToDouble() ? 0 : 2)} ต่อข้อความ',
              style: const TextStyle(fontSize: 11.5, color: JuntraColors.textLavender),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg, this.onRetry, this.onCopy});

  final _Msg msg;
  final VoidCallback? onRetry;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final maxW = MediaQuery.sizeOf(context).width * 0.78;

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
    } else {
      bg = JuntraColors.bgPurpleDeep.withValues(alpha: 0.7);
      fg = JuntraColors.textLavender;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment:
            msg.fromUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                msg.fromUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!msg.fromUser && !msg.isSystem) ...[
                const _MorAvatar(size: 28),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                  // คำตอบของแม่หมอใช้ **ตัวหนา** และ bullet เป็นปกติ
                  // เดิมใช้ Text ธรรมดา ผู้ใช้จึงเห็นดอกจันดิบเต็มไปหมด
                  child: msg.fromUser || msg.isSystem
                      ? Text(msg.text,
                          style: TextStyle(fontSize: 13.5, color: fg, height: 1.55))
                      : MarkdownBody(
                          data: msg.text,
                          selectable: true,
                          styleSheet: _markdownStyle(fg),
                        ),
                ),
              ),
            ],
          ),
          if (onRetry != null || onCopy != null)
            Padding(
              padding: EdgeInsets.only(
                top: 2,
                left: msg.fromUser ? 0 : 34,
                right: msg.fromUser ? 2 : 0,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onRetry != null)
                    TextButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh, size: 14),
                      label: const Text('ลองส่งใหม่', style: TextStyle(fontSize: 11.5)),
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
                      constraints: const BoxConstraints(minWidth: 30, minHeight: 26),
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
            fontWeight: FontWeight.w700, color: JuntraColors.textCream),
        em: const TextStyle(
            fontStyle: FontStyle.italic, color: JuntraColors.purpleBright),
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
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          const _MorAvatar(size: 28),
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
                  child: Container(
                    width: 6, height: 6,
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

/// แถบปุ่มคำถามลัด — ตรรกะเดียวกับเว็บเป๊ะ
///
///  1. คุยต่อไม่ได้ → ปุ่มทางออกที่กดได้จริงเสมอ (ไม่ใช่ปุ่มตาย)
///  2. แม่หมอกำลังถามกลับ → ยุบเหลือปุ่มเดียว เพราะถ้าผู้ใช้กดคำถามทั่วไป
///     ตอนนี้ บอทจะตีความเป็นคำตอบของคำถามที่ค้างอยู่ แล้วโฟลว์ทำนายพัง
///  3. ปกติ → แถวชิปเลื่อนแนวนอน
class _SuggestionStrip extends StatelessWidget {
  const _SuggestionStrip({
    required this.suggestions,
    required this.awaiting,
    required this.open,
    required this.blocked,
    required this.blockedReason,
    required this.busy,
    required this.onOpen,
    required this.onPick,
  });

  final List<_Suggestion> suggestions;
  final bool awaiting;
  final bool open;
  final bool blocked;
  final String blockedReason;
  final bool busy;
  final VoidCallback onOpen;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    if (blocked) {
      return _wrap(context, const SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          _ExitChip(icon: '🔮', label: 'เปิดไพ่ยิปซี', route: Routes.spreads, strong: true),
          _ExitChip(icon: '🌙', label: 'ดวงรายวัน', route: Routes.horoscope),
          _ExitChip(icon: '🔢', label: 'เลขศาสตร์', route: Routes.numerology),
          _ExitChip(icon: '📿', label: 'ฤกษ์ยาม', route: Routes.auspicious),
          _ExitChip(icon: '💳', label: 'เติมเครดิต', route: Routes.wallet, strong: true),
        ]),
      ), label: blockedReason.isEmpty ? 'ลองทางนี้ต่อได้เลยค่ะ' : blockedReason);
    }

    if (suggestions.isEmpty) return const SizedBox.shrink();

    if (awaiting && !open) {
      return _wrap(
        context,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            const Expanded(
              child: Text('💬 แม่หมอกำลังรอคำตอบของลูกอยู่ค่ะ',
                  style: TextStyle(fontSize: 12, color: JuntraColors.textMuted)),
            ),
            _Chip(label: 'ดูคำถามแนะนำ', onTap: onOpen),
          ]),
        ),
      );
    }

    return _wrap(
      context,
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: suggestions
              .map((s) => _Chip(
                    icon: s.icon,
                    label: s.label,
                    // ระหว่างแม่หมอพิมพ์ ชิปยังอยู่ที่เดิมแต่กดไม่ได้ (จางลง)
                    // เลย์เอาต์จึงไม่กระโดดและผู้ใช้ไม่งงว่าปุ่มหายไปไหน
                    onTap: busy ? null : () => onPick(s.prompt),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _wrap(BuildContext context, Widget child, {String? label}) {
    return Container(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(
          color: JuntraColors.gold.withValues(alpha: 0.10),
        )),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: Text(label,
                  style: const TextStyle(fontSize: 11, color: JuntraColors.textFaint)),
            ),
          child,
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({this.icon, required this.label, this.onTap, this.strong = false});

  final String? icon;
  final String label;
  final VoidCallback? onTap;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Opacity(
      opacity: disabled ? 0.42 : 1,
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: JuntraColors.gold.withValues(alpha: strong ? 0.22 : 0.09),
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: JuntraColors.gold.withValues(alpha: strong ? 0.65 : 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Text(icon!, style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 6),
                  ],
                  Text(label,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: strong ? JuntraColors.textCream : JuntraColors.textLavender,
                        fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
                      )),
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
      onTap: () => context.push(route),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.onSend,
    this.enabled = true,
    this.blockedReason,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final bool enabled;
  final String? blockedReason;

  @override
  Widget build(BuildContext context) {
    final blocked = blockedReason != null;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      decoration: BoxDecoration(
        color: JuntraColors.bgDeepest.withValues(alpha: 0.85),
        border: Border(top: BorderSide(
          color: JuntraColors.gold.withValues(alpha: 0.2),
        )),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: enabled,
                style: const TextStyle(color: JuntraColors.textCream, fontSize: 14),
                cursorColor: JuntraColors.gold,
                minLines: 1, maxLines: 4,
                maxLength: 2000,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => enabled ? onSend() : null,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: blocked
                      ? blockedReason
                      : 'พิมพ์ข้อความถึงแม่หมอ...',
                  hintStyle: const TextStyle(
                    color: JuntraColors.textFaint, fontSize: 13,
                  ),
                  filled: true,
                  fillColor: JuntraColors.bgPurpleDeep.withValues(alpha: 0.6),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // ปุ่มที่กดไม่ได้ต้อง "ดูกดไม่ได้" ชัดเจน ไม่ใช่ทองเต็มใบเหมือนกดได้
            Opacity(
              opacity: enabled ? 1.0 : 0.4,
              child: InkWell(
                onTap: enabled ? onSend : null,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: enabled ? JuntraColors.goldButtonGradient : null,
                    color: enabled ? null : JuntraColors.bgPurple,
                  ),
                  child: Icon(
                    blocked ? Icons.lock_outline : Icons.send_rounded,
                    color: enabled ? JuntraColors.bgPurpleDeep : JuntraColors.textFaint,
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
