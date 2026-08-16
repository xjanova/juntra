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

  // ─── ตัวละคร / โลโก้ ─────────────────────────────────────────
  static const maeMor = 'assets/images/maehmor.webp';
  static const logo = 'assets/images/logo-chantra.webp';

  /// ภาพประจำราศี — [slug] เป็น slug เดียวกับที่ /v1/horoscope ส่งมา
  /// (aries…pisces) จึงจับคู่กับ API ได้โดยไม่ต้องแปลงชื่อ
  static String zodiac(String slug) => '$_zodiac/$slug.webp';

  /// ราศีทั้ง 12 ตามลำดับโหราศาสตร์ — ใช้ตรวจว่าไฟล์ครบในเทสต์
  static const zodiacSlugs = <String>[
    'aries', 'taurus', 'gemini', 'cancer', 'leo', 'virgo',
    'libra', 'scorpio', 'sagittarius', 'capricorn', 'aquarius', 'pisces',
  ];
}
