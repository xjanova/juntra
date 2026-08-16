import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../data/juntra_art.dart';

/// แบนเนอร์ภาพประจำหมวด
///
/// กติกาสองข้อที่คุมไว้ในคอมโพเนนต์นี้ ไม่ปล่อยให้แต่ละหน้าทำเอง:
///
/// 1. **ภาพหายต้องไม่ทำหน้าพัง** — `errorBuilder` ยุบเป็น `SizedBox.shrink()`
///    ไม่ใช่ไอคอนรูปแตก หน้าที่เรียกจึงเหลือแค่หัวเรื่องเหมือนเดิม
/// 2. **ตัวหนังสือบนภาพต้องอ่านออกเสมอ** — ถ้ามี [overlay] จะปูสกริม
///    ไล่เฉดจากดำล่างขึ้นบน ไม่ต้องหวังพึ่งว่าภาพจะมืดพอเอง
///
/// `cacheWidth` ผูกกับความกว้างจริงที่วาด × devicePixelRatio เสมอ —
/// ไฟล์ต้นทางกว้าง 1200px ถ้าไม่กำหนดจะ decode เต็มความละเอียดลง RAM
/// ทุกครั้งที่หน้าโหลด (บั๊กเดิมของสแปลชที่โหลด maehmor.png 1536×2752)
class ArtBanner extends StatelessWidget {
  const ArtBanner({
    super.key,
    required this.asset,
    this.height = 150,
    this.radius = JuntraRadius.card,
    this.overlay,
    this.alignment = Alignment.center,
    this.margin,
  });

  final String asset;
  final double height;
  final double radius;

  /// เนื้อหาที่จะวางทับภาพ (หัวเรื่อง/คำโปรย) — จะได้สกริมอัตโนมัติ
  final Widget? overlay;
  final Alignment alignment;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final w = MediaQuery.sizeOf(context).width;

    return Container(
      margin: margin,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.25)),
        color: JuntraColors.bgPurpleDeep,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            asset,
            fit: BoxFit.cover,
            alignment: alignment,
            cacheWidth: (w * dpr).round(),
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
          if (overlay != null)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xE60A0414), Color(0x800A0414), Color(0x1A0A0414)],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
          if (overlay != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Align(alignment: Alignment.bottomLeft, child: overlay),
            ),
        ],
      ),
    );
  }
}

/// เส้นคั่นลายกนกไทย — ใช้แทนช่องว่างเปล่าระหว่างเซกชัน
///
/// ไฟล์ต้นทางเป็น WebP แบบ lossless ที่คีย์พื้นดำเป็นอัลฟาไว้แล้ว (ทำตอน
/// ตกแต่งเว็บ) จึงวางบนพื้นหลังดาวได้เลยโดยไม่ต้องใช้ blend mode
class ThaiDivider extends StatelessWidget {
  const ThaiDivider({super.key, this.height = 18, this.opacity = 0.75});
  final double height;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final w = MediaQuery.sizeOf(context).width;
    return Opacity(
      opacity: opacity,
      child: Image.asset(
        JuntraArt.divider,
        height: height,
        fit: BoxFit.contain,
        cacheWidth: (w * dpr).round(),
        errorBuilder: (_, _, _) => SizedBox(height: height),
      ),
    );
  }
}

/// สถานะว่าง — ภาพจัตุรัส + ข้อความ + ปุ่มชวนทำต่อ (ถ้ามี)
///
/// แทนที่กล่องข้อความเปล่าและ emoji ที่เคยใช้ในหน้าประวัติ/รายการแชท
/// emoji ถูกวาดด้วยฟอนต์ของเครื่องผู้ใช้ คุมโทนทอง-ม่วงไม่ได้เลย
class EmptyStateArt extends StatelessWidget {
  const EmptyStateArt({
    super.key,
    required this.asset,
    required this.title,
    this.message,
    this.action,
    this.size = 168,
  });

  final String asset;
  final String title;
  final String? message;
  final Widget? action;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(size / 2),
            child: Image.asset(
              asset,
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: (size * dpr).round(),
              errorBuilder: (_, _, _) => SizedBox(width: size, height: size),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: baiJamjuree(size: 16),
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5, color: JuntraColors.textMuted, height: 1.6,
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
    );
  }
}

/// ตราราศี — ภาพวงกลมประจำราศีพร้อมขอบทอง
///
/// ถ้าไฟล์หาย ตกไปเป็นสัญลักษณ์ราศี (glyph) แบบเดิม จึงไม่มีทางเห็นช่องว่าง
class ZodiacBadge extends StatelessWidget {
  const ZodiacBadge({
    super.key,
    required this.slug,
    required this.glyph,
    this.size = 56,
    this.selected = false,
  });

  final String slug;
  final String glyph;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: JuntraColors.bgPurpleDeep,
        border: Border.all(
          color: selected
              ? JuntraColors.gold
              : JuntraColors.gold.withValues(alpha: 0.35),
          width: selected ? 2 : 1,
        ),
      ),
      child: Image.asset(
        JuntraArt.zodiac(slug),
        fit: BoxFit.cover,
        cacheWidth: (size * dpr).round(),
        errorBuilder: (_, _, _) => Center(
          child: Text(
            glyph,
            style: TextStyle(fontSize: size * 0.45, color: JuntraColors.gold),
          ),
        ),
      ),
    );
  }
}
