/// ทะเบียนภาพประกอบของแอพ — ที่เดียวที่รู้ว่าไฟล์ไหนอยู่ path ไหน
///
/// ภาพชุดนี้แบ่งเป็นสองกลุ่ม:
///
/// 1. **เจนใหม่สำหรับแอพ** (art/chat, auth, natal, deep, share, horoscope,
///    history, palmistry, account + state/*) — ใช้ภาพแม่หมอจันทราต้นฉบับ
///    (`assets/images/maehmor.webp`) เป็นตัวอ้างอิงตัวละคร หน้าตาจึงเป็น
///    คนเดียวกันทุกใบ
/// 2. **ชุดเดียวกับเว็บ** (art/tarot, numerology, auspicious, wallet, mlm,
///    thai-zodiac, tarot-free + zodiac 12 ราศี + ลายไทย) — คัดลอกมาจาก
///    `juntraweb/public/images/juntra/` ตรง ๆ เพื่อให้คนที่ใช้ทั้งเว็บและแอพ
///    เห็นภาพชุดเดียวกัน ไม่ใช่คนละแบรนด์
///
/// ทุกไฟล์เป็น WebP ย่อไว้ที่ความกว้างที่ใช้จริงบนมือถือแล้ว (แบนเนอร์ 1200px,
/// ราศี 600px) — อย่าใส่ไฟล์ต้นฉบับความละเอียดเต็มลงมาที่นี่
class JuntraArt {
  JuntraArt._();

  static const _art = 'assets/images/art';
  static const _state = 'assets/images/state';
  static const _zodiac = 'assets/images/zodiac';
  static const _orn = 'assets/images/ornament';
  static const _category = 'assets/images/category';

  // ─── แบนเนอร์ประจำหมวด (16:9) ────────────────────────────────
  static const tarot = '$_art/tarot.webp';
  static const tarotFree = '$_art/tarot-free.webp';
  static const horoscope = '$_art/horoscope.webp';
  static const thaiZodiac = '$_art/thai-zodiac.webp';
  static const numerology = '$_art/numerology.webp';
  static const palmistry = '$_art/palmistry.webp';
  static const auspicious = '$_art/auspicious.webp';
  static const deep = '$_art/deep.webp';
  static const chat = '$_art/chat.webp';
  static const wallet = '$_art/wallet.webp';
  static const mlm = '$_art/mlm.webp';
  static const account = '$_art/account.webp';
  static const auth = '$_art/auth.webp';
  static const natal = '$_art/natal.webp';
  static const history = '$_art/history.webp';
  static const share = '$_art/share.webp';

  // ─── ภาพสถานะว่าง (1:1) ──────────────────────────────────────
  /// ยังไม่มีคำทำนาย — แม่หมอนั่งรอข้างผ้าปูไพ่ที่ยังไม่ได้เปิด
  static const stateNoReading = '$_state/no-reading.webp';

  /// ต้องเข้าสู่ระบบก่อน — แม่หมอยื่นกุญแจให้หน้าประตูทอง
  static const stateLocked = '$_state/locked.webp';

  // ─── ลายไทย / พื้นหลัง ───────────────────────────────────────
  static const divider = '$_orn/divider.webp';
  static const frameThai = '$_orn/frame-thai.webp';
  static const nebula = '$_orn/nebula.webp';

  /// พื้นเนบิวลาเต็มจอของเว็บ (`/images/juntra/bg-nebula.webp`, `.bg-fixed::after`)
  static const bgNebula = '$_orn/bg-nebula.webp';

  // ─── ตัวละคร / โลโก้ ─────────────────────────────────────────
  static const maeMor = 'assets/images/maehmor.webp';
  static const logo = 'assets/images/logo-chantra.webp';

  /// โลโก้ตัดขอบโปร่งใสออกแล้ว (240px) สำหรับมุมขวาบนของทุกหน้า — ใช้ไฟล์เต็ม
  /// [logo] ตรงนั้นจะเหลือขนาดจริงแค่ ~70% ของกรอบ เพราะภาพมีขอบใสเยอะ
  static const logoMark = 'assets/images/logo-chantra-mark.webp';

  /// หลังไพ่ — ลายเดียวกับ `card_back_url` ของเว็บ (คัดลอกมาเก็บในแอพ)
  ///
  /// พัดไพ่ 78 ใบต้องขึ้นทันทีโดยไม่รอเน็ต จึงใช้ไฟล์ในเครื่อง ส่วนไพ่ใบเด่น
  /// (บินขึ้นมา/กำลังพลิก) ยังดึงจากเว็บเหมือนเดิม — ลายต้องตรงกันทั้งสองทาง
  /// ไม่งั้นไพ่ที่ลูกแตะเลือกจะเปลี่ยนลายกลางแอนิเมชัน
  static const cardBack = 'assets/images/card-back.webp';

  /// การ์ดหมวดดูดวงบนหน้าแรก (2:3 ทรงไพ่) — [id] คือ `FortuneCategory.id`
  ///
  /// ชุดนี้เจนด้วย ChatGPT ในห้องเดียวกันทั้ง 8 ใบ (กติกาเดียวกัน: ม่วงคราม +
  /// ลายกนกทอง + จันทร์เสี้ยว ครึ่งล่างมืดไว้วางชื่อหมวด) ต้นฉบับ 1024×1536
  /// อยู่ที่ `art-src/category/` นอกรีโป
  static String category(String id) => '$_category/$id.webp';

  /// ภาพประจำราศี — [slug] เป็น slug เดียวกับที่ /v1/horoscope ส่งมา
  /// (aries…pisces) จึงจับคู่กับ API ได้โดยไม่ต้องแปลงชื่อ
  static String zodiac(String slug) => '$_zodiac/$slug.webp';

  // ─── ชุดเว็บ 2026-11 (ธีม juntra-payakorn) ───────────────────
  // ก๊อปจาก juntraweb/public/images/juntra/ — ภาพชุดเดียวกับที่ลูกค้าเห็นบนเว็บ

  /// ภาพห้องผู้พยากรณ์ — [key] = busaba · maemor · kunsai (rooms/{key}.webp)
  static String room(String key) => 'assets/images/rooms/$key.webp';

  /// ฉากโต๊ะของห้อง (theater plate) — rooms/plate-{key}.webp
  static String roomPlate(String key) => 'assets/images/rooms/plate-$key.webp';

  /// ภาพประจำแพ็กเกจไพ่ — [key] = single · three · quick · … · kunsai
  static String spread(String key) => 'assets/images/spreads/$key.webp';

  /// สไลด์หน้าแรก (ภาพเดียวกับ hero ของเว็บ)
  static const heroSlides = <String>[
    'assets/images/hero/maemor-1.webp',
    'assets/images/hero/busaba-1.webp',
    'assets/images/hero/maemor-2.webp',
    'assets/images/hero/busaba-2.webp',
    'assets/images/hero/maemor-3.webp',
    'assets/images/hero/busaba-3.webp',
    'assets/images/hero/maemor-4.webp',
    'assets/images/hero/maemor-5.webp',
  ];

  /// ป้ายเช็กอินต่อเนื่อง (DailyLuck::MILESTONES 3 · 7 · 14 · 30 วัน)
  static String streakBadge(int days) => 'assets/images/badges/streak-$days.webp';

  /// ภาพหน้าบัญชีชุดใหม่ของเว็บ
  static const collection = '$_art/collection.webp';
  static const dailyLuck = '$_art/daily-luck.webp';
  static const review = '$_art/review.webp';

  /// ราศีทั้ง 12 ตามลำดับโหราศาสตร์ — ใช้ตรวจว่าไฟล์ครบในเทสต์
  static const zodiacSlugs = <String>[
    'aries', 'taurus', 'gemini', 'cancer', 'leo', 'virgo',
    'libra', 'scorpio', 'sagittarius', 'capricorn', 'aquarius', 'pisces',
  ];
}
