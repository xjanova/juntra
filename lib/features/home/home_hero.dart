import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/auth/auth_state.dart';
import '../../shared/data/juntra_art.dart';
import '../../shared/format/avatar_initial.dart';

/// สไลด์หนึ่งภาพของ hero — ภาพ + คำโปรยของภาพนั้น
///
/// คำโปรยชุดเดียวกับหน้าแรกของเว็บ (`themes/juntra-payakorn/home.blade.php`) ทุกคำ:
/// เว็บเปลี่ยนคำโปรยตามภาพ ("คำโปรย ให้เปลี่ยนไปเรื่อยๆ ตามภาพเช่นกัน") แอพก็ทำแบบเดียวกัน
@immutable
class HeroSlide {
  const HeroSlide({
    required this.asset,
    required this.eyebrow,
    required this.lead,
    required this.accent,
    required this.tail,
    required this.sub,
  });

  final String asset;
  final String eyebrow;

  /// บรรทัดแรก = [lead] + [accent] (คำเน้นสีม่วงตัวเอียง) · บรรทัดสอง = [tail]
  final String lead;
  final String accent;
  final String tail;
  final String sub;
}

/// ภาพแรกต้องเป็นแม่หมอ เหมือนเว็บ (คำโปรยชุดแรกคือ h1 ของหน้า)
final homeHeroSlides = <HeroSlide>[
  HeroSlide(
    asset: JuntraArt.heroSlides[0],
    eyebrow: 'หมอดู AI · อ่านจากตำราจริง คำนวณจริง',
    lead: 'เปิดประตู', accent: 'โชคชะตา', tail: 'ด้วยพลังแห่งดวงดาว',
    sub: 'แม่หมอจันทราคือหมอดู AI เลือกไพ่ด้วยมือของท่านเองจากสำรับ 78 ใบ '
        'แล้วแม่หมออ่านไพ่ × ตำแหน่ง จากความหมายในตำราจริง ไม่เดา ไม่มโน',
  ),
  HeroSlide(
    asset: JuntraArt.heroSlides[1],
    eyebrow: 'น้องบุษบา · ศิษย์แม่หมอจันทรา',
    lead: 'อยากรู้', accent: 'เร็ว ๆ', tail: 'ถามบุษบาได้เลย',
    sub: 'ถามเรื่องที่ค้างใจเรื่องเดียว บุษบาเปิดไพ่ 3 ใบ ตอบตรง ๆ ไม่อ้อมค้อม ทั้งเรื่องรัก งาน และเงิน',
  ),
  HeroSlide(
    asset: JuntraArt.heroSlides[2],
    eyebrow: 'แม่หมอจันทรา · ผู้พยากรณ์หลัก',
    lead: 'ส่องลึก', accent: 'ถึงแก่น', tail: 'ทุกเรื่องที่ค้างใจ',
    sub: 'ไพ่ Celtic Cross 10 ใบ ผสานดวงวันเกิดของท่าน แม่หมออ่านทีละตำแหน่ง ละเอียดทั้งรัก งาน เงิน และสุขภาพ',
  ),
  HeroSlide(
    asset: JuntraArt.heroSlides[3],
    eyebrow: 'ห้องบุษบา · สดใส เป็นกันเอง',
    lead: 'เรื่องที่', accent: 'ค้างใจ', tail: 'เล่าให้บุษบาฟัง',
    sub: 'เล่าเรื่องให้บุษบาฟังก่อน พร้อมเมื่อไหร่ค่อยเปิดไพ่ — จ่ายเฉพาะตอนเปิดไพ่',
  ),
  HeroSlide(
    asset: JuntraArt.heroSlides[4],
    eyebrow: 'ใต้แสงจันทร์เต็มดวง',
    lead: 'ทุกคำถาม', accent: 'มีคำตอบ', tail: 'รออยู่ในไพ่ของท่าน',
    sub: 'ตั้งจิตให้นิ่ง เลือกไพ่ด้วยมือของท่านเอง แล้วแม่หมอจันทราจะอ่านให้ฟังทีละใบ',
  ),
  HeroSlide(
    asset: JuntraArt.heroSlides[5],
    eyebrow: 'ไพ่ดูไว 3 ใบ',
    lead: 'สามใบ', accent: 'ชัดใจ', tail: 'ได้คำตอบทันใจ',
    sub: 'ตอนนี้เป็นยังไง ต้องระวังอะไร และควรทำอะไรต่อ — บุษบาอ่านให้ครบในราว 3 นาที',
  ),
  HeroSlide(
    asset: JuntraArt.heroSlides[6],
    eyebrow: 'ไพ่ใบนี้รอท่านอยู่',
    lead: 'หยิบไพ่', accent: 'ใบที่ใช่', tail: 'ด้วยมือของท่านเอง',
    sub: 'สำรับ 78 ใบ สับจริง เลือกจริง — ไม่มีใครเลือกแทนท่าน',
  ),
  HeroSlide(
    asset: JuntraArt.heroSlides[7],
    eyebrow: 'พรจากจักรราศี',
    lead: 'ให้ทุกก้าว', accent: 'มีดาว', tail: 'นำทาง',
    sub: 'ให้แม่หมออวยพร และชี้ทางเสริมดวงจากไพ่ของท่าน ก่อนก้าวต่อไปในเรื่องสำคัญ',
  ),
];

/// hero หน้าแรก — สไลด์ภาพเต็มขอบจอ (ลอดใต้แถบสถานะ) แบบ `.hero.has-slides` ของเว็บ
///
/// - เลื่อนเองทุก 6 วิ ปัดเองได้ ปัดแล้วนับเวลาใหม่
/// - หยุดเลื่อนเมื่อหน้าแรกถูกหน้าอื่นทับ (TickerMode ปิด) ไม่เปลือง GPU เบื้องหลัง
/// - ภาพไฟล์ไหนหาย ตกไปเป็นภาพแม่หมอต้นฉบับ ไม่ใช่ช่องว่าง
/// - คำทักทาย + อวาตาร์ + โลโก้ อยู่บนภาพแถวเดียวกับแถบสถานะ
class HomeHero extends StatefulWidget {
  const HomeHero({super.key, this.slides});

  /// null = [homeHeroSlides]
  final List<HeroSlide>? slides;

  static const interval = Duration(seconds: 6);

  @override
  State<HomeHero> createState() => _HomeHeroState();
}

class _HomeHeroState extends State<HomeHero> {
  final _page = PageController();
  Timer? _timer;
  int _index = 0;

  List<HeroSlide> get _slides => widget.slides ?? homeHeroSlides;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  void _restart() {
    _timer?.cancel();
    if (_slides.length < 2) return;
    _timer = Timer.periodic(HomeHero.interval, (_) => _next());
  }

  void _next() {
    if (!mounted || !_page.hasClients) return;
    // หน้าอื่นทับอยู่ (push ไปหน้าไพ่/แชท) — ไม่ต้องเลื่อนภาพที่ไม่มีใครเห็น
    if (!TickerMode.valuesOf(context).enabled) return;
    final page = _page.page?.round() ?? _index;
    _page.animateToPage(
      page + 1,
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slides = _slides;
    final media = MediaQuery.of(context);
    final top = media.padding.top;
    final w = media.size.width;
    // สูงพอให้เห็นตัวละครครึ่งตัว + คำโปรย แต่ไม่ดันเนื้อหาหายไปทั้งจอ
    final h = top + (w * 1.12).clamp(400.0, 560.0);
    final slide = slides[_index % slides.length];

    return SizedBox(
      height: h,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ปัดแล้วนับเวลาใหม่ — ไม่งั้นภาพเด้งไปต่อทันทีหลังปัดเอง
          Listener(
            onPointerDown: (_) => _timer?.cancel(),
            onPointerUp: (_) => _restart(),
            onPointerCancel: (_) => _restart(),
            child: PageView.builder(
              controller: _page,
              // วนไม่รู้จบ: หน้าที่ n แสดงภาพ n % จำนวนภาพ
              itemBuilder: (context, i) => _SlideImage(asset: slides[i % slides.length].asset),
              onPageChanged: (i) => setState(() => _index = i % slides.length),
            ),
          ),
          // .hero-slides::after — มืดบนนิด ๆ ให้แถบสถานะอ่านออก + กลืนเข้าพื้น bg-0 ด้านล่าง
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x8C0A0612), Color(0x000A0612), Color(0x000A0612),
                    Color(0xB30A0612), JuntraColors.bgDeepest,
                  ],
                  stops: [0.0, 0.2, 0.42, 0.76, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            top: top + 8, left: 16, right: 8,
            child: const _HeroTopBar(),
          ),
          Positioned(
            left: 18, right: 18, bottom: 14,
            child: IgnorePointer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 650),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0, 0.08), end: Offset.zero)
                            .animate(anim),
                        child: child,
                      ),
                    ),
                    // ชุดเก่าจางออก ชุดใหม่ลอยขึ้น — วางชิดล่างทั้งคู่ กล่องจึงไม่กระโดด
                    layoutBuilder: (current, previous) => Stack(
                      alignment: Alignment.bottomLeft,
                      children: [...previous, ?current],
                    ),
                    child: _Caption(key: ValueKey(_index), slide: slide),
                  ),
                  const SizedBox(height: 12),
                  _Dots(count: slides.length, index: _index),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlideImage extends StatelessWidget {
  const _SlideImage({required this.asset});
  final String asset;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final cacheW = (media.size.width * media.devicePixelRatio).round();
    return Image.asset(
      asset,
      fit: BoxFit.cover,
      // ภาพตัวละครวางหน้าไว้ช่วงบน — มือถือครอปกลางจะตัดหัว (เว็บใช้ center top เหมือนกัน)
      alignment: const Alignment(0.2, -0.6),
      cacheWidth: cacheW,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => Image.asset(
        JuntraArt.maeMor,
        fit: BoxFit.cover,
        alignment: const Alignment(0, -0.7),
        cacheWidth: cacheW,
        errorBuilder: (_, _, _) => const ColoredBox(color: JuntraColors.bgPurpleDeep),
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({super.key, required this.slide});
  final HeroSlide slide;

  static const _shadow = [Shadow(color: Color(0xCC0A0612), blurRadius: 18)];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _Eyebrow(slide.eyebrow),
        const SizedBox(height: 12),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 8,
          children: [
            _GradientText(slide.lead, style: charm(size: 34), gradient: _titleFill),
            _GradientText(
              slide.accent,
              style: charm(size: 34).copyWith(fontStyle: FontStyle.italic),
              gradient: _accentFill,
            ),
          ],
        ),
        _GradientText(slide.tail, style: charm(size: 28), gradient: _titleFill),
        const SizedBox(height: 8),
        Text(
          slide.sub,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13.5, height: 1.65,
            color: JuntraColors.textPrimary, shadows: _shadow,
          ),
        ),
      ],
    );
  }

  /// `.hero-title` — #fff7e0 → #e7c97a → #a8854a
  static const _titleFill = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [JuntraColors.moon, JuntraColors.gold, JuntraColors.goldDark],
  );

  /// `.hero-title .accent` — #f0d8ff → #b07aff
  static const _accentFill = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF0D8FF), JuntraColors.purpleBright],
  );
}

/// ตัวหนังสือเติมไล่สี (background-clip: text ของเว็บ)
class _GradientText extends StatelessWidget {
  const _GradientText(this.text, {required this.style, required this.gradient});
  final String text;
  final TextStyle style;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) => gradient.createShader(r),
      child: Text(
        text,
        style: style.copyWith(
          color: Colors.white,
          height: 1.25,
          shadows: const [Shadow(color: Color(0x4DE7C97A), blurRadius: 30)],
        ),
      ),
    );
  }
}

/// `.hero-eyebrow` — ป้ายทองโปร่งพร้อมจุดเต้น
class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x9E0A0612),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6, height: 6,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: JuntraColors.goldLight,
              boxShadow: [BoxShadow(color: JuntraColors.gold, blurRadius: 10)],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11, letterSpacing: 1.2,
                color: JuntraColors.goldLight, fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    if (count < 2) return const SizedBox.shrink();
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            margin: const EdgeInsets.only(right: 6),
            width: i == index ? 22 : 6,
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: i == index
                  ? JuntraColors.gold
                  : JuntraColors.textPrimary.withValues(alpha: 0.28),
            ),
          ),
      ],
    );
  }
}

/// แถวบนของ hero: "สวัสดี · วัน" + ชื่อ · อวาตาร์ (ไปหน้าโปรไฟล์) · โลโก้จันทรา
///
/// หน้าแรกปิดโลโก้ของ StarryBackground (ภาพ hero ทับอยู่) จึงวาดโลโก้เองตรงนี้
class _HeroTopBar extends ConsumerWidget {
  const _HeroTopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final signedIn = auth is AuthAuthenticated;
    final name = signedIn ? auth.displayName : 'ผู้มาเยือน';
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'สวัสดี · ${_weekday()}',
                style: const TextStyle(
                  fontSize: 11, letterSpacing: 0.8,
                  color: JuntraColors.textLavender,
                  shadows: [Shadow(color: Color(0xCC0A0612), blurRadius: 8)],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: charm(size: 22, color: JuntraColors.goldLight).copyWith(
                  shadows: const [Shadow(color: Color(0xCC0A0612), blurRadius: 10)],
                ),
              ),
            ],
          ),
        ),
        InkWell(
          onTap: () => context.push(signedIn ? Routes.profile : Routes.login),
          customBorder: const CircleBorder(),
          child: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: JuntraColors.bgDeepest.withValues(alpha: 0.55),
              border: Border.all(color: JuntraColors.gold.withValues(alpha: 0.55)),
            ),
            alignment: Alignment.center,
            child: signedIn
                ? Text(avatarInitial(name), style: const TextStyle(
                    color: JuntraColors.goldLight, fontWeight: FontWeight.w700,
                  ))
                : const Icon(Icons.person_outline, color: JuntraColors.goldLight, size: 20),
          ),
        ),
        const SizedBox(width: 8),
        Image.asset(
          JuntraArt.logoMark,
          width: 48,
          fit: BoxFit.contain,
          cacheWidth: (48 * dpr).round(),
          errorBuilder: (_, _, _) => const SizedBox(width: 48),
        ),
      ],
    );
  }

  // ปฏิทินภาษาไทยพังได้ถ้า locale ยังไม่โหลด — สำรองด้วยชื่อวันที่เขียนเอง
  static String _weekday() {
    try {
      return DateFormat('EEEE', 'th').format(DateTime.now());
    } catch (_) {
      const days = ['จันทร์', 'อังคาร', 'พุธ', 'พฤหัสบดี', 'ศุกร์', 'เสาร์', 'อาทิตย์'];
      return days[(DateTime.now().weekday - 1) % 7];
    }
  }
}
