import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../shared/widgets/starry_background.dart';

/// Screen 7 — Mae Mor AI chat.
///
/// In production, [_send] hits `POST /v1/chat/mae-mor/send` which proxies
/// to the FortuneAIService pool (Gemini 2.5-flash + Claude). The system
/// prompt makes the model answer in Mae Mor's voice ("ลูก", warm-mystical).
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_Msg>[
    _Msg.bot('สวัสดีค่ะลูก แม่หมอจันทราอยู่ตรงนี้แล้ว · '
        'อยากปรึกษาเรื่องอะไรเป็นพิเศษวันนี้คะ?'),
  ];
  bool _typing = false;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(_Msg.user(text));
      _typing = true;
    });
    _controller.clear();
    _scrollToEnd();

    // TODO: wire to /v1/chat/mae-mor/send (uses Thaiprompt FortuneAIService pool)
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    setState(() {
      _typing = false;
      _messages.add(_Msg.bot(_canned(text)));
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent + 80,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
      }
    });
  }

  String _canned(String q) {
    return 'ลูก... แม่หมอเห็นสิ่งที่ลูกถามชัดเจนแล้ว · '
        'ดวงตอนนี้แสดงให้เห็นว่าเป็นช่วงเวลาแห่งการเปลี่ยนผ่าน '
        'อย่ารีบตัดสินใจในสิ่งที่ใจยังลังเล รอดวงจันทร์ขึ้นเต็มดวง '
        'แล้วค่อยฟังเสียงของหัวใจตัวเองอีกครั้งนะคะ ✨';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const StarryBackground(density: 30, intensity: 0.4),
          SafeArea(
            child: Column(
              children: [
                _Header(),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    itemCount: _messages.length + (_typing ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (_typing && i == _messages.length) {
                        return const _TypingBubble();
                      }
                      return _Bubble(msg: _messages[i]);
                    },
                  ),
                ),
                _InputBar(controller: _controller, onSend: _send),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
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
            onPressed: () => context.go(Routes.home),
          ),
          ClipOval(
            child: Image.asset('assets/images/maehmor.png',
                width: 40, height: 40, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 40, height: 40,
                  color: JuntraColors.bgPurple,
                  alignment: Alignment.center,
                  child: const Text('🔮'),
                )),
          ),
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
                    const Text('ออนไลน์ · ตอบใน 8 วิ',
                        style: TextStyle(
                          fontSize: 10, color: JuntraColors.textMuted,
                        )),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz, color: JuntraColors.textMuted),
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

class _Msg {
  _Msg({required this.text, required this.fromUser});
  final String text;
  final bool fromUser;
  factory _Msg.user(String t) => _Msg(text: t, fromUser: true);
  factory _Msg.bot(String t) => _Msg(text: t, fromUser: false);
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg});
  final _Msg msg;
  @override
  Widget build(BuildContext context) {
    final color = msg.fromUser
        ? JuntraColors.gold.withValues(alpha: 0.18)
        : JuntraColors.bgPurpleDeep.withValues(alpha: 0.7);
    final textColor = msg.fromUser ? JuntraColors.textCream : JuntraColors.textLavender;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: msg.fromUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!msg.fromUser) ...[
            ClipOval(
              child: Image.asset('assets/images/maehmor.png',
                  width: 28, height: 28, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 28, height: 28, color: JuntraColors.bgPurple,
                    alignment: Alignment.center,
                    child: const Text('🔮', style: TextStyle(fontSize: 14)),
                  )),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: const BoxConstraints(maxWidth: 280),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(msg.fromUser ? 14 : 4),
                  bottomRight: Radius.circular(msg.fromUser ? 4 : 14),
                ),
                border: msg.fromUser
                    ? Border.all(color: JuntraColors.gold.withValues(alpha: 0.4))
                    : null,
              ),
              child: Text(msg.text, style: TextStyle(
                fontSize: 13.5, color: textColor, height: 1.55,
              )),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.2);
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
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

class _InputBar extends StatelessWidget {
  const _InputBar({required this.controller, required this.onSend});
  final TextEditingController controller;
  final VoidCallback onSend;
  @override
  Widget build(BuildContext context) {
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
                style: const TextStyle(color: JuntraColors.textCream, fontSize: 14),
                cursorColor: JuntraColors.gold,
                minLines: 1, maxLines: 4,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: 'พิมพ์ข้อความถึงแม่หมอ...',
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
            InkWell(
              onTap: onSend,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 44, height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: JuntraColors.goldButtonGradient,
                ),
                child: const Icon(Icons.send_rounded,
                    color: JuntraColors.bgPurpleDeep, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
