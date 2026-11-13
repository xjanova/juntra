import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/api/api_exceptions.dart';
import '../../core/auth/auth_state.dart';
import '../../core/auth/social_auth.dart';

class SocialLoginPanel extends ConsumerStatefulWidget {
  const SocialLoginPanel({
    super.key,
    required this.onAuthenticated,
    required this.onBusyChanged,
    this.disabled = false,
    this.referralCode,
  });
  final VoidCallback onAuthenticated;
  final ValueChanged<bool> onBusyChanged;
  final bool disabled;
  final String? Function()? referralCode;

  @override
  ConsumerState<SocialLoginPanel> createState() => _SocialLoginPanelState();
}

class _SocialLoginPanelState extends ConsumerState<SocialLoginPanel>
    with WidgetsBindingObserver {
  SocialLoginTicket? _ticket;
  SocialPkce? _proof;
  String? _provider;
  String? _error;
  Timer? _pollTimer;
  Timer? _expiryTimer;
  bool _busy = false;
  bool _polling = false;
  bool _finishing = false;
  bool _foreground = true;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _pollTimer?.cancel();
    if (_foreground && _ticket != null) unawaited(_poll());
  }

  @override
  void dispose() {
    ++_epoch;
    _pollTimer?.cancel();
    _expiryTimer?.cancel();
    _proof = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _stop([String? error]) {
    ++_epoch;
    _pollTimer?.cancel();
    _expiryTimer?.cancel();
    setState(() {
      _ticket = null;
      _proof = null;
      _busy = false;
      _polling = false;
      _finishing = false;
      _provider = null;
      _error = error;
    });
    widget.onBusyChanged(false);
  }

  void _schedule([Duration? delay]) {
    _pollTimer?.cancel();
    if (!_foreground || _ticket == null) return;
    _pollTimer = Timer(delay ?? _ticket!.pollInterval, _poll);
  }

  Future<void> _start(SocialProvider provider) async {
    if (_busy || widget.disabled) return;
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _provider = provider.name;
      _error = null;
    });
    widget.onBusyChanged(true);
    try {
      final proof = SocialPkce.generate();
      final repo = await ref.read(socialAuthRepositoryProvider.future);
      if (!mounted || epoch != _epoch) return;
      final ticket = await repo.start(
        provider: provider.id,
        proof: proof,
        referralCode: widget.referralCode?.call()?.trim().replaceAll(
          RegExp(r'[^A-Za-z0-9_-]'),
          '',
        ),
      );
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _ticket = ticket;
        _proof = proof;
      });
      _expiryTimer = Timer(ticket.expiresAt.difference(DateTime.now()), () {
        if (mounted && epoch == _epoch && !_finishing) {
          _stop('หมดเวลาเข้าสู่ระบบ กรุณาลองใหม่อีกครั้ง');
        }
      });
      final opened = await ref.read(socialBrowserLauncherProvider)(ticket.url);
      if (!mounted || epoch != _epoch) return;
      if (!opened) {
        _stop('เปิดหน้าล็อกอินไม่ได้ กรุณาตรวจสอบเบราว์เซอร์แล้วลองใหม่');
        return;
      }
      _schedule();
    } on ApiException catch (e) {
      if (mounted && epoch == _epoch) {
        _stop(
          e.statusCode == 404
              ? 'การเข้าสู่ระบบด้วยโซเชียลยังไม่พร้อม กรุณาลองใหม่ภายหลัง'
              : e.message,
        );
      }
    } catch (_) {
      if (mounted && epoch == _epoch) {
        _stop('เริ่มเข้าสู่ระบบไม่ได้ กรุณาลองใหม่อีกครั้ง');
      }
    }
  }

  Future<void> _poll() async {
    final ticket = _ticket;
    final proof = _proof;
    if (!mounted ||
        !_foreground ||
        _polling ||
        _finishing ||
        ticket == null ||
        proof == null) {
      return;
    }
    if (!DateTime.now().isBefore(ticket.expiresAt)) {
      _stop('หมดเวลาเข้าสู่ระบบ กรุณาลองใหม่อีกครั้ง');
      return;
    }
    final epoch = _epoch;
    setState(() => _polling = true);
    var delay = ticket.pollInterval;
    try {
      final repo = await ref.read(socialAuthRepositoryProvider.future);
      if (!mounted || epoch != _epoch) return;
      final result = await repo.poll(id: ticket.id, proof: proof);
      if (!mounted || epoch != _epoch) return;
      switch (result.status) {
        case SocialLoginStatus.authorized:
          setState(() => _finishing = true);
          _expiryTimer?.cancel();
          await ref
              .read(authControllerProvider.notifier)
              .completeSocialSignIn(result);
          if (!mounted || epoch != _epoch) return;
          _stop();
          widget.onAuthenticated();
          return;
        case SocialLoginStatus.cancelled:
          _stop('ยกเลิกการเข้าสู่ระบบแล้ว');
          return;
        case SocialLoginStatus.expired:
          _stop('ลิงก์เข้าสู่ระบบหมดอายุ กรุณาลองใหม่อีกครั้ง');
          return;
        case SocialLoginStatus.failed:
          _stop(result.message ?? 'เข้าสู่ระบบไม่สำเร็จ กรุณาลองใหม่อีกครั้ง');
          return;
        case SocialLoginStatus.pending:
          setState(() => _error = null);
      }
    } on ApiException catch (e) {
      if (!mounted || epoch != _epoch) return;
      if ([400, 401, 403, 404, 410, 422].contains(e.statusCode)) {
        _stop(
          e.statusCode == 404 || e.statusCode == 410
              ? 'ลิงก์เข้าสู่ระบบหมดอายุ กรุณาลองใหม่อีกครั้ง'
              : e.message,
        );
        return;
      }
      if (_finishing) {
        _stop('บันทึกการเข้าสู่ระบบไม่สำเร็จ กรุณาลองใหม่อีกครั้ง');
        return;
      }
      delay = const Duration(seconds: 10);
      setState(
        () => _error = e.statusCode == 429
            ? 'กำลังรอยืนยัน กรุณารอสักครู่'
            : 'การเชื่อมต่อสะดุด กำลังลองตรวจสอบอีกครั้ง',
      );
    } catch (_) {
      if (!mounted || epoch != _epoch) return;
      _stop('ยืนยันการเข้าสู่ระบบไม่สำเร็จ กรุณาลองใหม่อีกครั้ง');
      return;
    } finally {
      if (mounted && epoch == _epoch) setState(() => _polling = false);
    }
    if (mounted && epoch == _epoch) _schedule(delay);
  }

  @override
  Widget build(BuildContext context) {
    final providers = ref.watch(socialProvidersProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_busy) ...[
          const Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: JuntraColors.gold,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _finishing
                ? 'กำลังเข้าสู่ระบบ...'
                : 'เข้าสู่ระบบด้วย $_provider ในเบราว์เซอร์ แล้วกลับมาที่แอปจันทรา',
            textAlign: TextAlign.center,
            style: const TextStyle(color: JuntraColors.textCream, height: 1.5),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton(
                onPressed: _polling || _finishing || _ticket == null
                    ? null
                    : _poll,
                child: const Text('ตรวจสถานะอีกครั้ง'),
              ),
              TextButton(
                onPressed: _finishing ? null : () => _stop(),
                child: const Text('ยกเลิก'),
              ),
            ],
          ),
        ] else ...[
          ...providers.when(
            data: (items) => [
              for (final provider in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: OutlinedButton.icon(
                    onPressed: widget.disabled ? null : () => _start(provider),
                    icon: provider.id == 'facebook'
                        ? const Icon(Icons.facebook, color: Color(0xFF589CFF))
                        : const Icon(Icons.account_circle_outlined),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'เข้าสู่ระบบด้วย ${provider.name}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 4),
                const Text(
                  'หรือใช้อีเมล / เบอร์โทรศัพท์',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: JuntraColors.textMuted),
                ),
                const SizedBox(height: 18),
              ],
            ],
            loading: () => [
              const Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 18),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ],
            error: (_, _) => [
              const Text(
                'โหลดวิธีเข้าสู่ระบบด้วยโซเชียลไม่ได้',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: JuntraColors.textMuted),
              ),
              TextButton(
                onPressed: widget.disabled
                    ? null
                    : () => ref.invalidate(socialProvidersProvider),
                child: const Text('ลองใหม่'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFFFB59A), height: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}
