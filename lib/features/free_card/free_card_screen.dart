import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/api/app_config_repository.dart';
import '../../core/api/fortune_repository.dart';
import '../../core/api/free_card_repository.dart';
import '../../core/api/idempotency.dart';
import '../../core/auth/session.dart';
import '../../shared/data/juntra_art.dart';
import '../../shared/widgets/art_banner.dart';
import '../../shared/widgets/gold_button.dart';
import '../../shared/widgets/starry_background.dart';

class FreeCardScreen extends ConsumerWidget {
  const FreeCardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigValueProvider);
    final user = ref.watch(sessionUserIdProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('ไพ่ฟรี 1 ใบ')),
      body: Stack(
        children: [
          const StarryBackground(density: 40, intensity: 0.5),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                ArtBanner(
                  asset: JuntraArt.tarotFree,
                  overlay: Text(
                    'ให้ไพ่ช่วยเปิดทางให้คุณ',
                    style: baiJamjuree(size: 20, color: JuntraColors.goldLight),
                  ),
                ),
                const SizedBox(height: 24),
                if (!config.has('free_reading') || !config.freeReading)
                  const Text('ยังไม่เปิดให้บริการ', textAlign: TextAlign.center)
                else if (user == null) ...[
                  const Text(
                    'เข้าสู่ระบบเพื่อรับไพ่ฟรี 1 ใบค่ะ',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  GoldButton(
                    label: 'เข้าสู่ระบบ',
                    onPressed: () => context.push(Routes.login),
                  ),
                ] else
                  // เปลี่ยนคน = ทิ้งคำถามและคำขอของบัญชีเก่า
                  _FreeCardForm(key: ValueKey(user), userId: user),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FreeCardForm extends ConsumerStatefulWidget {
  const _FreeCardForm({super.key, required this.userId});
  final String userId;

  @override
  ConsumerState<_FreeCardForm> createState() => _FreeCardFormState();
}

class _FreeCardFormState extends ConsumerState<_FreeCardForm> {
  final _question = TextEditingController();
  final _attempt = IdempotentAttempt('free-card');
  bool _busy = false;
  bool _unsupported = false;
  String? _error;

  bool get _current =>
      mounted && ref.read(sessionUserIdProvider) == widget.userId;

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _claim(FreeCardState state) async {
    if (_busy || !state.available) return;
    FocusScope.of(context).unfocus();
    final question = _question.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = await ref.read(freeCardRepositoryProvider.future);
      if (!_current) return;
      final result = await repo.claim(
        question: question,
        idempotencyKey: _attempt.begin(question),
      );
      if (!mounted || !_current) return;
      _attempt.succeeded();
      final cid = result.conversationId;
      if (cid != null) {
        ref
            .read(freeCardConversationsProvider.notifier)
            .update((old) => {...old, result.readingId: cid});
      }
      ref.invalidate(freeCardStatusProvider);
      ref.invalidate(fortuneHistoryProvider);
      context.pushReplacement('${Routes.reading}?id=${result.readingId}');
    } on ApiException catch (e) {
      if (!_current) return;
      setState(() {
        _unsupported = e.statusCode == 404;
        _error = e.statusCode == 401
            ? freeCardReasonText('no_token')
            : e.message;
      });
      if (e.statusCode == 401 || e.statusCode == 403 || e.statusCode == 409) {
        ref.invalidate(freeCardStatusProvider);
      }
      // ไม่รู้ว่าคำขอถึงเซิร์ฟเวอร์หรือยัง = เก็บคีย์เดิมไว้สำหรับลองใหม่
    } catch (_) {
      if (!_current) return;
      setState(
        () => _error = 'เปิดไพ่ไม่สำเร็จ ตรวจสอบสัญญาณแล้วลองใหม่อีกครั้งนะคะ',
      );
    } finally {
      if (_current) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(freeCardStatusProvider);
    if (_unsupported) {
      return const Text('ยังไม่เปิดให้บริการ', textAlign: TextAlign.center);
    }
    return status.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: JuntraColors.gold),
      ),
      error: (e, _) => Column(
        children: [
          Text(
            e is ApiException
                ? e.message
                : 'โหลดสิทธิ์ไพ่ฟรีไม่สำเร็จ ลองใหม่อีกครั้งนะคะ',
            textAlign: TextAlign.center,
          ),
          TextButton(
            onPressed: () => ref.invalidate(freeCardStatusProvider),
            child: const Text('ลองใหม่'),
          ),
          if (e is ApiException && e.statusCode == 401)
            TextButton(
              onPressed: () => context.push(Routes.login),
              child: const Text('เข้าสู่ระบบ'),
            ),
        ],
      ),
      data: (state) {
        if (state == null || state.needsLogin) {
          return GoldButton(
            label: 'เข้าสู่ระบบ',
            onPressed: () => context.push(Routes.login),
          );
        }
        if (!state.supported) {
          return const Text('ยังไม่เปิดให้บริการ', textAlign: TextAlign.center);
        }
        if (!state.available) {
          return Column(
            children: [
              Text(state.reasonText(), textAlign: TextAlign.center),
              if (state.readingId != null)
                TextButton(
                  onPressed: () =>
                      context.push('${Routes.reading}?id=${state.readingId}'),
                  child: const Text('ดูคำทำนายที่รับไว้'),
                ),
              if (!state.claimed && !state.disabled)
                TextButton(
                  onPressed: () => ref.invalidate(freeCardStatusProvider),
                  child: const Text('ตรวจสอบอีกครั้ง'),
                ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'ตั้งคำถามในใจ หรือเขียนเรื่องที่อยากให้ไพ่ช่วยชี้ทางค่ะ',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _question,
              enabled: !_busy,
              // max_chars ของ D1 จำกัดคำตอบ AI; คำถาม D2 รับได้ 500 ตัวอักษร
              maxLength: 500,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'คำถาม (ไม่บังคับ)'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: JuntraColors.gold),
                ),
              ),
            const SizedBox(height: 16),
            GoldButton(
              label: _busy ? 'กำลังเปิดไพ่ให้คุณ…' : 'รับไพ่ฟรี 1 ใบ',
              disabled: _busy,
              onPressed: () => _claim(state),
            ),
          ],
        );
      },
    );
  }
}
