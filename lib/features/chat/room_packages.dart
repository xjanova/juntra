import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/rooms_repository.dart';
import '../../core/api/tarot_packages_repository.dart';
import '../../shared/format/credits.dart';

/// แพ็กเกจไพ่ที่ห้องนี้ขายตอนนี้ — แบบประจำห้องขึ้นก่อน แล้วตามลำดับ `spreads` ของเซิร์ฟเวอร์
///
/// เซิร์ฟเวอร์เก่า/ห้องในเครื่อง: `spreads` เป็นชุดสำรองจาก config ของเว็บ ·
/// แพ็กเกจที่ปิดขายไปแล้วไม่อยู่ใน [all] จึงหลุดออกเอง
List<TarotPackage> roomPackages(OracleRoom room, List<TarotPackage> all) {
  final byKey = {for (final p in all) p.key: p};
  final own = room.product?.spread;
  final order = <String>[
    if (own != null && own.isNotEmpty) own,
    ...room.spreads,
  ];
  final out = <TarotPackage>[];
  for (final k in order) {
    final p = byKey.remove(k);
    if (p != null) out.add(p);
  }
  // ห้องที่เซิร์ฟเวอร์ไม่บอก spreads เลย — เลือกตามห้องของแพ็กเกจแทน
  if (out.isEmpty && room.spreads.isEmpty) {
    out.addAll(all.where((p) => p.roomKey == room.key));
  }
  return out;
}

/// ราคาแพ็กเกจแบบเว็บ ("฿39" / "39 เครดิต" / "ฟรี") — null = ไม่รู้ราคา (ออฟไลน์ไม่มีแคช)
String? packagePriceLabel(TarotPackage p) {
  if (p.free) return 'ฟรี';
  final price = p.price;
  if (price == null) return null;
  return price <= 0 ? 'ฟรี' : formatCredits(price);
}

/// หนึ่งแถวแพ็กเกจ (เว็บ `.room-product`) — จำนวนใบ · ชื่อ · ราคา
class RoomPackageRow extends StatelessWidget {
  const RoomPackageRow({super.key, required this.package, required this.accent, this.onTap});

  final TarotPackage package;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final price = packagePriceLabel(package);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
            child: Text('${package.cards}',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: JuntraColors.textCream)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(package.nameTh,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: JuntraColors.textLavender, height: 1.35)),
          ),
          if (price != null) ...[
            const SizedBox(width: 8),
            Text(price,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: JuntraColors.gold)),
          ],
          if (onTap != null) ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: JuntraColors.gold),
          ],
        ],
      ),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: JuntraColors.bgDeepest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(JuntraRadius.input),
        border: Border.all(color: JuntraColors.lineSoft),
      ),
      child: onTap == null
          ? row
          : Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(JuntraRadius.input),
                child: row,
              ),
            ),
    );
  }
}

/// "เปิดไพ่ชุดใหม่" — แผงแพ็กเกจของห้อง แตะแล้วเข้าซีนสับไพ่ในแอพ
class RoomPackagesSheet extends ConsumerWidget {
  const RoomPackagesSheet({super.key, required this.room});

  final OracleRoom room;

  static Future<void> show(BuildContext context, OracleRoom room) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: JuntraColors.bgPurpleDeep,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => RoomPackagesSheet(room: room),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tarotPackagesProvider);
    final list = roomPackages(room, async.valueOrNull ?? const []);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
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
              const SizedBox(height: 14),
              Text('เปิดไพ่ชุดใหม่กับ${room.short}', style: baiJamjuree(size: 18, color: JuntraColors.gold)),
              const SizedBox(height: 4),
              const Text('เลือกแบบไพ่ที่อยากเปิด — ราคาไพ่หักตอนเปิดไพ่เท่านั้น',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: JuntraColors.textMuted)),
              const SizedBox(height: 14),
              if (async.isLoading && list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: JuntraColors.gold),
                  ),
                )
              else if (list.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('ตอนนี้ห้องนี้ยังไม่มีแบบไพ่เปิดขายค่ะ ลองใหม่อีกครั้งภายหลังนะคะ',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: JuntraColors.textMuted, height: 1.6)),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final p in list)
                        RoomPackageRow(
                          package: p,
                          accent: room.accent,
                          onTap: () {
                            // จับ router ไว้ก่อนปิดแผง — context ของแผงใช้ไม่ได้แล้วหลัง pop
                            final router = GoRouter.of(context);
                            Navigator.of(context).pop();
                            router.push('${Routes.shuffle}?spread=${Uri.encodeQueryComponent(p.key)}');
                          },
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
