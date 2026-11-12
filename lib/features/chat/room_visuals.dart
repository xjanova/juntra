import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/api/rooms_repository.dart';
import '../../core/voice/media_url.dart';

/// ภาพผู้พยากรณ์ของห้อง — ภาพจากเซิร์ฟเวอร์ → ภาพห้องในเครื่อง → ภาพแม่หมอเดิม → 🔮
///
/// ทุกจุดที่วาดผู้พยากรณ์ (หน้าเลือกห้อง · หัวห้องแชท · ฟองข้อความ · รายการบทสนทนา) ใช้ตัวนี้
/// ภาพห้องจะได้ตรงกันทุกหน้า และไม่มีจุดไหนเหลือภาพแม่หมอค้างอยู่ในห้องบุษบา
class RoomImage extends StatelessWidget {
  const RoomImage({
    super.key,
    required this.roomKey,
    this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
    this.decodeWidth,
  });

  final String roomKey;
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;

  /// ความกว้างที่ decode จริง (logical px) — ภาพแม่หมอเดิม 1536×2752 ถ้าไม่จำกัด
  /// จะ decode เต็มความละเอียดลง RAM ทุกครั้งที่วาดอวตาร 28 px
  final double? decodeWidth;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final w = decodeWidth ?? width;
    final px = w == null ? null : (w * dpr).round();
    final local = OracleRoom.builtIn(roomKey).localImage;

    Widget asset(String path, Widget Function() onError) => Image.asset(
          path,
          width: width,
          height: height,
          fit: fit,
          alignment: alignment,
          cacheWidth: px,
          errorBuilder: (_, _, _) => onError(),
        );

    Widget emoji() => Container(
          width: width,
          height: height,
          color: JuntraColors.bgPurple,
          alignment: Alignment.center,
          child: Text('🔮', style: TextStyle(fontSize: (width ?? 40) * 0.45)),
        );

    Widget offline() => asset(local, () => asset(OracleRoom.fallbackImage, emoji));

    final url = imageUrl;
    if (url == null) return offline();
    return CachedNetworkImage(
      imageUrl: mediaUrl(url),
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      memCacheWidth: px,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (_, _) => offline(),
      errorWidget: (_, _, _) => offline(),
    );
  }
}

/// อวตารกลมของผู้พยากรณ์ — ขอบสีประจำห้อง
class RoomAvatar extends StatelessWidget {
  const RoomAvatar({
    super.key,
    required this.roomKey,
    this.imageUrl,
    this.size = 40,
    this.accent,
    this.ring = true,
  });

  final String roomKey;
  final String? imageUrl;
  final double size;
  final Color? accent;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? OracleRoom.builtIn(roomKey).accent;
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(ring ? 1.5 : 0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ring ? color.withValues(alpha: 0.75) : null,
        boxShadow: ring ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: size * 0.3)] : null,
      ),
      child: ClipOval(
        child: RoomImage(
          roomKey: roomKey,
          imageUrl: imageUrl,
          width: size,
          height: size,
        ),
      ),
    );
  }
}

/// ป้าย "AI" ของผู้พยากรณ์ (เว็บ `<x-ai-badge>`) — บอกตรง ๆ ว่าห้องนี้คือหมอดู AI
class AiBadge extends StatelessWidget {
  const AiBadge({super.key, this.large = false});

  /// true = บนการ์ดห้อง · false = ข้างชื่อในหัวห้องแชท
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'หมอดู AI — อ่านไพ่จากความหมายในตำราไพ่ 78 ใบ ไม่เดา ไม่มโน',
      child: Semantics(
        label: 'ผู้พยากรณ์ปัญญาประดิษฐ์',
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: large ? 9 : 7, vertical: large ? 4 : 2),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [JuntraColors.purple, JuntraColors.magenta]),
            borderRadius: BorderRadius.circular(JuntraRadius.chip),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 0.8),
            boxShadow: [
              BoxShadow(color: JuntraColors.magenta.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 2)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome, size: large ? 11 : 9, color: Colors.white),
              const SizedBox(width: 3),
              Text('AI',
                  style: TextStyle(
                    fontSize: large ? 11 : 10,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: Colors.white,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

/// จุดเขียว "ออนไลน์"
class OnlineDot extends StatelessWidget {
  const OnlineDot({super.key, this.size = 7});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: JuntraColors.mintGreen,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: JuntraColors.mintGreen.withValues(alpha: 0.6), blurRadius: size)],
      ),
    );
  }
}
