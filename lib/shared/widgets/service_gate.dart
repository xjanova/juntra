import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/app_config_repository.dart';
import 'gold_button.dart';
import 'starry_background.dart';

/// บริการที่หลังบ้านปิดขายชั่วคราว (ServiceGate — สวิตช์ชุดเดียวกับเว็บ) → หน้าบอกเหตุผล
///
/// หน้าแรกซ่อนปุ่มของบริการที่ปิดแล้ว แต่ยังเข้าถึงได้จากลิงก์เก่า/ปุ่มในแชท/ประวัติ —
/// ต้องไม่เปิดฟอร์มให้กรอกแล้วค่อยโดน 503 ตอนกดส่ง (ของเดิมเป็นแบบนั้น)
class ServiceGate extends ConsumerWidget {
  const ServiceGate({super.key, required this.service, required this.name, required this.child});

  /// คีย์ของ ServiceGate ฝั่งเซิร์ฟเวอร์: numerology · auspicious · palmistry · deep · horoscope
  final String service;
  final String name;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(appConfigProvider);
    return async.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator(color: JuntraColors.gold)),
      ),
      error: (_, _) => child,
      data: (cfg) => cfg.isOpen(service) ? child : _ClosedScreen(name: name),
    );
  }
}

class _ClosedScreen extends StatelessWidget {
  const _ClosedScreen({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const StarryBackground(density: 40, intensity: 0.5),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.chevron_left, color: JuntraColors.gold, size: 28),
                    onPressed: () => context.canPop() ? context.pop() : context.go(Routes.home),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.construction_rounded, color: JuntraColors.gold, size: 44),
                          const SizedBox(height: 14),
                          Text('$name ปิดปรับปรุงชั่วคราว',
                              textAlign: TextAlign.center,
                              style: baiJamjuree(size: 19, color: JuntraColors.gold)),
                          const SizedBox(height: 10),
                          const Text(
                            'แม่หมอกำลังปรับให้ผลคำนวณตรงตามตำราและปฏิทินหลวงทุกวัน · ยังไม่มีการหักเครดิต\nระหว่างนี้เปิดไพ่หรือคุยกับแม่หมอได้ตามปกติค่ะ',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: JuntraColors.textLavender, height: 1.6),
                          ),
                          const SizedBox(height: 20),
                          GoldButton(label: 'เปิดไพ่ยิปซี', onPressed: () => context.go(Routes.spreads)),
                          const SizedBox(height: 6),
                          GhostButton(label: 'คุยกับแม่หมอ', onPressed: () => context.go(Routes.chat)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
