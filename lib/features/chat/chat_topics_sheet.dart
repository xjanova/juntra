import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/deep_repository.dart';

/// แผงหมวดคำถาม 24 ข้อ — ชุดเดียวกับที่เว็บกางในแชท
///
/// ดึงจาก GET /v1/chat/topics ซึ่งอ่านจาก App\Support\ChatSuggestions ฝั่ง
/// เซิร์ฟเวอร์ ไม่ hardcode ในแอพ ไม่งั้นแก้คำถามบนเว็บแล้วแอพไม่ตาม
/// (บทเรียนเดิม: spread catalog เคย hardcode ในแอพจน drift กับ backend)
///
/// คืนคำถามที่ผู้ใช้เลือกผ่าน Navigator.pop — null = ปิดโดยไม่เลือก
class ChatTopicsSheet extends ConsumerWidget {
  const ChatTopicsSheet({super.key});

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: JuntraColors.bgPurpleDeep,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => const ChatTopicsSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topics = ref.watch(chatTopicsProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      builder: (_, scroll) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: JuntraColors.gold.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          Text('อยากถามเรื่องไหนคะ',
              style: baiJamjuree(size: 18, color: JuntraColors.gold)),
          const SizedBox(height: 4),
          const Text('แตะคำถามที่ตรงใจ แม่หมอจะตอบให้เลยค่ะ',
              style: TextStyle(fontSize: 12.5, color: JuntraColors.textMuted)),
          const SizedBox(height: 12),
          Expanded(
            child: topics.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: JuntraColors.gold),
              ),
              error: (_, _) => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'โหลดหมวดคำถามไม่สำเร็จค่ะ\nพิมพ์ถามแม่หมอตรง ๆ ได้เลยนะคะ',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: JuntraColors.textMuted, height: 1.7),
                  ),
                ),
              ),
              data: (list) => ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final t = list[i];
                  final prompts = ((t['prompts'] as List?) ?? const [])
                      .map((p) => p.toString())
                      .toList();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 14, bottom: 8),
                        child: Text(
                          '${t['icon'] ?? ''} ${t['label'] ?? ''}',
                          style: baiJamjuree(size: 14.5, color: JuntraColors.gold),
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: prompts
                            .map((p) => _PromptChip(
                                  text: p,
                                  onTap: () => Navigator.of(context).pop(p),
                                ))
                            .toList(),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PromptChip extends StatelessWidget {
  const _PromptChip({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: JuntraColors.gold.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width - 64,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.3)),
          ),
          child: Text(text,
              style: const TextStyle(
                fontSize: 12.5, color: JuntraColors.textLavender, height: 1.4,
              )),
        ),
      ),
    );
  }
}
