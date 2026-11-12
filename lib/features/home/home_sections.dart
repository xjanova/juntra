import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/api/app_config_repository.dart';
import '../../core/api/rooms_repository.dart';
import '../../core/api/tarot_packages_repository.dart';
import '../../core/api/testimonials_repository.dart';
import '../../core/auth/auth_state.dart';
import '../../shared/data/juntra_art.dart';
import '../../shared/format/credits.dart';
import '../../shared/widgets/gold_button.dart';

/// หัวข้อแต่ละส่วนแบบ `.section-head` ของเว็บ: eyebrow ตัวเอียงทอง · หัวข้อ Charm ไล่สี ·
/// ลายกนกคั่น · คำโปรยสั้น
class HomeSectionHead extends StatelessWidget {
  const HomeSectionHead({
    super.key,
    required this.eyebrow,
    required this.title,
    this.sub,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String? sub;

  /// ลิงก์ "ดูทั้งหมด →" ท้ายหัวข้อ
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow.toUpperCase(),
          textAlign: TextAlign.start,
          style: cinzel(size: 12, color: JuntraColors.gold).copyWith(letterSpacing: 3),
        ),
        const SizedBox(height: 6),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) => JuntraColors.headlineGradient.createShader(r),
          child: Text(
            title,
            textAlign: TextAlign.start,
            style: baiJamjuree(size: 19, color: Colors.white).copyWith(height: 1.3, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 4),
        if (sub != null) ...[
          const SizedBox(height: 6),
          Text(
            sub!,
            textAlign: TextAlign.start,
            style: const TextStyle(fontSize: 13, color: JuntraColors.textLavender, height: 1.7),
          ),
        ],
        if (trailing != null) ...[
          const SizedBox(height: 6),
          trailing!,
        ],
      ],
    );
  }
}

/// ลิงก์ทองเล็ก ๆ "ดูทั้งหมด →"
class HomeLink extends StatelessWidget {
  const HomeLink({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(label, style: const TextStyle(
          fontSize: 12.5, color: JuntraColors.goldLight, fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        )),
      ),
    );
  }
}

/// พื้นการ์ดแบบ `.service` ของเว็บ
BoxDecoration homeCardDecoration({Color? accent, double radius = 22}) => BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xD1241038), Color(0xD10F081C)],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: (accent ?? JuntraColors.gold).withValues(alpha: accent == null ? 0.22 : 0.45)),
      boxShadow: [
        if (accent != null)
          BoxShadow(color: accent.withValues(alpha: 0.18), blurRadius: 24, spreadRadius: -6),
        ...JuntraShadows.cardDeep,
      ],
    );

/// ภาพจากเซิร์ฟเวอร์ → ไฟล์ในแอพ → ไฟล์สำรองสุดท้าย (ไม่มีวันเห็นช่องแตก)
class HomeArt extends StatelessWidget {
  const HomeArt({
    super.key,
    this.url,
    required this.asset,
    this.fallbackAsset = JuntraArt.tarot,
    this.alignment = Alignment.center,
    required this.decodeWidth,
  });

  final String? url;
  final String asset;
  final String fallbackAsset;
  final Alignment alignment;

  /// ความกว้างที่วาดจริง (logical px) — ใช้จำกัดขนาด decode
  final double decodeWidth;

  @override
  Widget build(BuildContext context) {
    final cacheW = (decodeWidth * MediaQuery.devicePixelRatioOf(context)).round();
    Widget local() => Image.asset(
          asset,
          fit: BoxFit.cover,
          alignment: alignment,
          cacheWidth: cacheW,
          errorBuilder: (_, _, _) => Image.asset(
            fallbackAsset,
            fit: BoxFit.cover,
            alignment: alignment,
            cacheWidth: cacheW,
            errorBuilder: (_, _, _) => const ColoredBox(color: JuntraColors.bgPurpleDeep),
          ),
        );
    if (url == null) return local();
    return CachedNetworkImage(
      imageUrl: url!,
      fit: BoxFit.cover,
      alignment: alignment,
      memCacheWidth: cacheW,
      placeholder: (_, _) => local(),
      errorWidget: (_, _, _) => local(),
    );
  }
}

// ───────────────────────────── ผู้พยากรณ์ ─────────────────────────────

/// ทางเข้าห้องผู้พยากรณ์แบบเว็บ — การ์ดเลื่อนแนวนอนหนึ่งใบต่อห้อง
///
/// เซิร์ฟเวอร์เปิดห้องเดียว/เซิร์ฟเวอร์เก่า → การ์ดแม่หมอใบเดียวเต็มแถว (เข้าแชทได้ทันที)
/// ไม่มีคำว่า "ออนไลน์" หรือ "ตอบใน N วิ" แบบตายตัวอีกแล้ว — ยอดคนออนไลน์จริงอยู่ในหน้าเลือกห้อง
class HomeRoomsStrip extends ConsumerWidget {
  const HomeRoomsStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(roomsValueProvider);
    final rooms = state.hasPicker ? state.rooms : [state.room(OracleRoom.defaultKey)];
    final w = MediaQuery.sizeOf(context).width;
    final single = rooms.length == 1;
    final cardW = single ? w - 32 : ((w - 56) / 3).clamp(88.0, 200.0);

    return Column(
      children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: HomeSectionHead(
          eyebrow: single ? 'Oracle · ผู้พยากรณ์' : 'Oracle Rooms · ${state.openRooms.length} ห้อง',
          title: single ? 'คุยกับแม่หมอจันทรา' : 'เลือกผู้พยากรณ์ของท่าน',
          sub: state.lede ?? 'เล่าเรื่องที่ค้างใจได้ก่อน พร้อมเมื่อไหร่ค่อยให้เปิดไพ่ — หักเครดิตเมื่อเปิดไพ่เท่านั้น',
        )),
        const SizedBox(height: 14),
        SizedBox(
          height: single ? 230 : (cardW * 1.5).clamp(150.0, 280.0),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: rooms.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _RoomCard(
              room: rooms[i],
              width: cardW,
              wide: single,
              lock: state.lock,
            ).animate().fadeIn(delay: (90 * i).ms, duration: 420.ms).slideX(begin: 0.06),
          ),
        ),
        if (state.aiDisclosure != null) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              state.aiDisclosure!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: JuntraColors.textDim, height: 1.6),
            ),
          ),
        ],
      ],
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({required this.room, required this.width, required this.wide, this.lock});
  final OracleRoom room;
  final double width;
  final bool wide;
  final RoomLock? lock;

  void _enter(BuildContext context) {
    if (!room.open) return;
    final l = lock;
    // ระหว่างทำนายในอีกห้อง เว็บไม่ให้ข้ามห้อง (ReadingRoomLock) — บอกเหตุผลแทนการพาเข้าไปแล้วโดนเด้ง
    if (l != null && l.active && l.room != room.key) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l.message ?? 'ตอนนี้ยังอยู่ระหว่างทำนายในอีกห้อง รอให้จบก่อนนะคะ'),
      ));
      return;
    }
    context.push('${Routes.chat}?room=${room.key}');
  }

  @override
  Widget build(BuildContext context) {
    final accent = room.accent;
    return SizedBox(
      width: width,
      child: Opacity(
        opacity: room.open ? 1 : 0.55,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: homeCardDecoration(accent: accent),
          child: Stack(
            fit: StackFit.expand,
            children: [
              HomeArt(
                url: room.imageUrl,
                asset: room.localImage,
                fallbackAsset: OracleRoom.fallbackImage,
                alignment: const Alignment(0, -0.5),
                decodeWidth: width,
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x000A0612), Color(0x330A0612), Color(0xE60A0612), Color(0xFA0A0612)],
                    stops: [0.0, 0.35, 0.72, 1.0],
                  ),
                ),
              ),
              Positioned(
                top: 12, left: 12,
                child: _Badge(label: room.open ? 'AI' : 'เร็ว ๆ นี้', color: accent),
              ),
              Positioned(
                left: wide ? 14 : 6, right: wide ? 14 : 6, bottom: wide ? 14 : 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (wide) Text(
                      room.eyebrow,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10.5, letterSpacing: 0.8, color: accent),
                    ),
                    const SizedBox(height: 2),
                    Text(room.short, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: baiJamjuree(size: wide ? 24 : 14, color: JuntraColors.goldLight)),
                    Text(
                      room.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5, color: JuntraColors.textPrimary, height: 1.45),
                    ),
                    if (wide) const SizedBox(height: 8),
                    if (wide) Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 4, runSpacing: 4,
                            children: [
                              for (final t in room.tags.take(2)) _Badge(label: t, color: accent, soft: true),
                            ],
                          ),
                        ),
                        if (room.open)
                          Icon(Icons.arrow_forward_rounded, color: accent, size: 20),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned.fill(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: room.open ? () => _enter(context) : null,
                    splashColor: accent.withValues(alpha: 0.18),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color, this.soft = false});
  final String label;
  final Color color;
  final bool soft;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: soft ? color.withValues(alpha: 0.12) : const Color(0xB30A0612),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: soft ? 0.3 : 0.6)),
      ),
      child: Text(label, style: TextStyle(
        fontSize: 10, color: soft ? JuntraColors.textPrimary : color,
        fontWeight: FontWeight.w600, letterSpacing: 0.5,
      )),
    );
  }
}

// ───────────────────────────── แพ็กเกจไพ่ ─────────────────────────────

/// "เลือกไพ่ที่ตรงกับคำถามของท่าน" — แพ็กเกจจากเซิร์ฟเวอร์ ราคาจริง ชื่อผู้อ่านจริง
///
/// แพ็กเกจที่เว็บขายเฉพาะในห้องแชท (`web_only`) ไม่แสดงที่นี่ เหมือนหน้าแรกของเว็บ
class HomePackages extends ConsumerWidget {
  const HomePackages({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(tarotPackagesProvider).valueOrNull;
    // ยังโหลดไม่เสร็จ = ไม่วาดอะไร (ไม่มีสปินเนอร์กระพริบบนหน้าแรก)
    if (all == null) return const SizedBox.shrink();
    final packages = all.where((p) => !p.webOnly).toList();
    if (packages.isEmpty) return const SizedBox.shrink();
    final w = MediaQuery.sizeOf(context).width;
    final cardW = (w * .4).clamp(140.0, 180.0);

    return Column(
      children: [
        HomeSectionHead(
          eyebrow: 'Tarot · ${packages.length} แพ็กเกจ',
          title: 'เลือกไพ่ที่ตรงกับคำถามของท่าน',
          sub: 'แม่หมอจันทราและน้องบุษบาอ่านไพ่ทีละตำแหน่ง ฟันธงให้ชัด — หักเครดิตเมื่อเปิดไพ่เท่านั้น',
          trailing: HomeLink(label: 'ดูแพ็กเกจทั้งหมด →', onTap: () => context.push(Routes.spreads)),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: cardW * 9 / 16 + 160,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: packages.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _PackageCard(package: packages[i], width: cardW),
          ),
        ),
      ],
    );
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({required this.package, required this.width});
  final TarotPackage package;
  final double width;

  @override
  Widget build(BuildContext context) {
    final p = package;
    final room = OracleRoom.builtIn(p.roomKey);
    final reader = p.readerName ?? room.short;
    final price = p.price;
    final priceText = price == null
        ? null
        : (p.free || price <= 0 ? 'ฟรี' : formatCredits(price));

    return SizedBox(
      width: width,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: homeCardDecoration(),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      HomeArt(
                        url: p.imageUrl,
                        asset: JuntraArt.spread(p.key),
                        decodeWidth: width,
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x000F081C), Color(0x000F081C), Color(0xD90F081C)],
                            stops: [0.0, 0.5, 1.0],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.nameTh,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: charm(size: 20, color: JuntraColors.goldLight),
                        ),
                        Text(
                          [ '${p.cards} ใบ', ?p.nameEn ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: JuntraColors.textDim, letterSpacing: 0.6),
                        ),
                        const SizedBox(height: 4),
                        if (p.tagline != null)
                          Text(
                            p.tagline!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: JuntraColors.textLavender, height: 1.5),
                          ),
                        const Spacer(),
                        Text(
                          'เปิดไพ่กับ$reader →',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: room.accent),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (priceText != null)
              Positioned(
                top: 10, right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xB80F081C),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.4)),
                  ),
                  child: Text(priceText, style: const TextStyle(
                    fontSize: 11.5, color: JuntraColors.goldLight,
                    fontWeight: FontWeight.w600, letterSpacing: 0.8,
                  )),
                ),
              ),
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: () => context.push('${Routes.shuffle}?spread=${p.key}'),
                  splashColor: JuntraColors.gold.withValues(alpha: 0.12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── ไพ่ฟรี ─────────────────────────────

/// "ดูดวงฟรี 1 ใบ" — แสดงเมื่อเซิร์ฟเวอร์เปิดไพ่ฟรี (`free_reading`) เท่านั้น
class HomeFreeCard extends ConsumerWidget {
  const HomeFreeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(appConfigValueProvider);
    if (!cfg.has('free_reading') || !cfg.freeReading) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: InkWell(
        onTap: () => context.push(Routes.freeCard),
        borderRadius: BorderRadius.circular(22),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: homeCardDecoration(accent: JuntraColors.purpleBright),
          child: Row(
            children: [
              const SizedBox(
                width: 118, height: 118,
                child: HomeArt(asset: JuntraArt.tarotFree, decodeWidth: 118),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('FREE CARD · สมาชิกใหม่', style: TextStyle(
                        fontSize: 10.5, letterSpacing: 1.4, color: JuntraColors.purpleBright,
                      )),
                      const SizedBox(height: 2),
                      Text('ดูดวงฟรี 1 ใบ', style: charm(size: 21, color: JuntraColors.goldLight)),
                      const SizedBox(height: 2),
                      const Text(
                        'ลองเปิดไพ่ 1 ใบ ทำนายสั้น ๆ ฟรี ก่อนตัดสินใจเปิดไพ่ชุดเต็ม',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: JuntraColors.textLavender, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(Icons.arrow_forward_rounded, color: JuntraColors.goldLight),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── รีวิว ─────────────────────────────

/// "เสียงจากผู้ที่เคยเปิดดวง" — เฉพาะรีวิวจริงที่ลูกค้ายินยอมให้แสดง
class HomeTestimonials extends ConsumerWidget {
  const HomeTestimonials({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(testimonialsProvider).valueOrNull ?? const <Testimonial>[];
    if (list.isEmpty) return const SizedBox.shrink();
    final w = MediaQuery.sizeOf(context).width;
    return Column(
      children: [
        const HomeSectionHead(
          eyebrow: 'Voices of Believers',
          title: 'เสียงจากผู้ที่เคยเปิดดวง',
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => _TestimonialCard(t: list[i], width: (w * .56).clamp(180.0, 260.0)),
          ),
        ),
      ],
    );
  }
}

class _TestimonialCard extends StatelessWidget {
  const _TestimonialCard({required this.t, required this.width});
  final Testimonial t;
  final double width;

  @override
  Widget build(BuildContext context) {
    final initial = t.name.characters.isEmpty ? '✦' : t.name.characters.first;
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: homeCardDecoration(radius: 20),
      child: Stack(
        children: [
          Positioned(
            top: -18, left: -6,
            child: Text('”', style: cinzel(size: 80, color: JuntraColors.goldDark.withValues(alpha: 0.3))),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('★' * t.rating, style: const TextStyle(
                color: JuntraColors.goldLight, fontSize: 14, letterSpacing: 2,
              )),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  t.message,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: JuntraColors.textLavender, height: 1.75),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: [JuntraColors.purpleBright, JuntraColors.magenta]),
                    ),
                    child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, color: JuntraColors.goldLight)),
                        if (t.service != null)
                          Text(t.service!, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: JuntraColors.textDim, letterSpacing: 0.6)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── DBD ─────────────────────────────

/// ตรา DBD Registered — ข้อมูลชุดเดียวกับ `config/business.php` ของเว็บ (ใบหมดอายุ 5 มิ.ย. 2574)
///
/// ตรวจของจริงได้ที่หน้ากรมพัฒนาธุรกิจการค้า (ลิงก์เปิดนอกแอพ — ไม่เกี่ยวกับการชำระเงิน)
class HomeDbdCard extends StatelessWidget {
  const HomeDbdCard({super.key});

  static const verifyUrl = 'https://dbdregistered.dbd.go.th/api/public/trustmarkinfo/125789';

  static const _facts = <(String, String)>[
    ('ชื่อร้าน', 'จันทราพยากรณ์ (CHANTHRAPAYAAKORN)'),
    ('เลขเครื่องหมาย', '125789'),
    ('ได้รับเมื่อ', '5 มิถุนายน 2569'),
    ('หมดอายุ', '5 มิถุนายน 2574'),
  ];

  Future<void> _verify(BuildContext context) async {
    final ok = await launchUrl(Uri.parse(verifyUrl), mode: LaunchMode.externalApplication)
        .catchError((_) => false);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เปิดหน้าตรวจสอบไม่ได้ ลองใหม่อีกครั้งนะคะ')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        decoration: homeCardDecoration(radius: 22),
        child: Column(
          children: [
            Image.asset(
              JuntraArt.dbdBadge,
              height: 44,
              cacheHeight: (44 * dpr).round(),
              errorBuilder: (_, _, _) => const Icon(Icons.verified_outlined, color: JuntraColors.gold, size: 40),
            ),
            const SizedBox(height: 10),
            Text('LICENSED · DBD REGISTERED',
                style: cinzel(size: 11.5, color: JuntraColors.gold).copyWith(letterSpacing: 2.5)),
            const SizedBox(height: 4),
            Text(
              'จดทะเบียนพาณิชย์อิเล็กทรอนิกส์\nกับกระทรวงพาณิชย์',
              textAlign: TextAlign.center,
              style: charm(size: 20, color: JuntraColors.goldLight).copyWith(height: 1.35),
            ),
            const SizedBox(height: 12),
            for (final (k, v) in _facts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 104,
                      child: Text(k, style: const TextStyle(fontSize: 12, color: JuntraColors.textDim)),
                    ),
                    Expanded(
                      child: Text(v, style: const TextStyle(fontSize: 12.5, color: JuntraColors.textPrimary)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            GhostButton(
              label: 'ตรวจสอบกับกรมพัฒนาธุรกิจการค้า ↗',
              onPressed: () => _verify(context),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────── CTA ─────────────────────────────

/// "พร้อมแล้วหรือยัง ที่จะรู้คำตอบ" — ท้ายหน้าแรกแบบ `.cta-strip`
class HomeCtaStrip extends ConsumerWidget {
  const HomeCtaStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final cfg = ref.watch(appConfigValueProvider);
    final signedIn = auth is AuthAuthenticated;
    final free = cfg.has('free_reading') && cfg.freeReading;

    final (String sub, String label, String route) = signedIn
        ? ('ยินดีต้อนรับ ${auth.displayName} — เลือกไพ่ที่ใจคุณเรียกหา', 'เลือกแพ็กเกจไพ่', Routes.spreads)
        : free
            ? ('สมัครสมาชิกฟรี แล้วรับคำทำนายไพ่ 1 ใบฟรี หรือคุยกับแม่หมอก่อนก็ได้', 'ดูดวงฟรี 1 ใบ', Routes.freeCard)
            : ('เข้าสู่ระบบเพื่อเก็บประวัติคำทำนาย แล้วเลือกไพ่ที่ใจคุณเรียกหา', 'เข้าสู่ระบบ', Routes.login);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0x597A3DF0), Color(0x33D24AD1), Color(0x26E7C97A)],
          ),
          border: Border.all(color: JuntraColors.line),
        ),
        child: Column(
          children: [
            Text('OPEN THE CARDS', style: cinzel(size: 12, color: JuntraColors.gold).copyWith(letterSpacing: 3)),
            const SizedBox(height: 6),
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (r) => JuntraColors.headlineGradient.createShader(r),
              child: Text(
                'พร้อมแล้วหรือยัง\nที่จะรู้คำตอบ',
                textAlign: TextAlign.center,
                style: charm(size: 26, color: Colors.white).copyWith(height: 1.3),
              ),
            ),
            const SizedBox(height: 8),
            Text(sub, textAlign: TextAlign.center, style: const TextStyle(
              fontSize: 13, color: JuntraColors.textLavender, height: 1.6,
            )),
            const SizedBox(height: 16),
            GoldButton(label: label, onPressed: () => context.push(route)),
          ],
        ),
      ),
    );
  }
}
