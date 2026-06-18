/// Tarot spread catalog — kept in lock-step with the juntraweb backend
/// registry `config/tarot_spreads.php`.
///
/// IMPORTANT: every [Spread.id] here equals a backend spread KEY, so the
/// saved reading type is simply `tarot_<id>` (see [Spread.backendType]).
/// That lets the shuffle cinematic POST any spread to
/// `/v1/history/readings` — the backend accepts all of these, debits the
/// wallet, runs the AI, and returns a persisted reading the app renders
/// generically. Card counts MUST match the backend or the API returns 422.
///
/// Prices here are FALLBACKS only — the live price comes from
/// `GET /v1/wallet` (`pricing.tarot_<id>`); see spreadPriceProvider.
class Spread {
  const Spread({
    required this.id,
    required this.name,
    required this.desc,
    required this.cards,
    required this.price,
    this.badge,
    this.popular = false,
    this.positions = const [],
  });
  final String id;
  final String name;
  final String desc;
  final int cards;
  final int price; // baht — fallback only; real price from /v1/wallet
  final String? badge;
  final bool popular;
  final List<String> positions; // labels per card slot

  /// Backend `Reading.type` for this spread. The backend keys its registry
  /// by the same id, so this is always `tarot_<id>`.
  String get backendType => 'tarot_$id';
}

const spreads = <Spread>[
  Spread(
    id: 'three', name: 'อดีต · ปัจจุบัน · อนาคต', desc: 'ไพ่ 3 ใบ เห็นที่มา–ที่เป็น–ที่ไป',
    cards: 3, price: 19, popular: true,
    positions: ['อดีต', 'ปัจจุบัน', 'อนาคต'],
  ),
  Spread(
    id: 'single', name: 'ไพ่ใบเดียว', desc: 'ถามตรง ตอบตรง ฟันธงเรื่องเดียว',
    cards: 1, price: 9, badge: 'เร็ว',
    positions: ['คำตอบของไพ่'],
  ),
  Spread(
    id: 'love', name: 'ความรัก / เนื้อคู่', desc: 'ใจคุณ · ใจเขา · ความสัมพันธ์ · อุปสรรค · ผลลัพธ์',
    cards: 5, price: 39, badge: 'ยอดฮิต',
    positions: ['ตัวคุณ', 'อีกฝ่าย', 'ความสัมพันธ์ระหว่างกัน', 'อุปสรรค / บทเรียน', 'แนวโน้มผลลัพธ์'],
  ),
  Spread(
    id: 'career', name: 'การงาน / การเงิน', desc: 'สถานการณ์ · จุดแข็ง · อุปสรรค · ทางออก · ผลลัพธ์',
    cards: 5, price: 39,
    positions: ['สถานการณ์ตอนนี้', 'จุดแข็ง / สิ่งที่หนุน', 'อุปสรรค / สิ่งที่ฉุด', 'สิ่งที่ควรทำ', 'แนวโน้มผลลัพธ์'],
  ),
  Spread(
    id: 'decision', name: 'ทางแยก / ตัดสินใจ', desc: 'ชั่งสองทางเลือก เห็นสิ่งที่มองข้าม',
    cards: 5, price: 39,
    positions: ['หัวใจของเรื่อง', 'ทางเลือกที่หนึ่ง', 'ทางเลือกที่สอง', 'สิ่งที่มองข้าม', 'คำแนะนำของไพ่'],
  ),
  Spread(
    id: 'celtic', name: 'เซลติกครอส', desc: 'วิเคราะห์เชิงลึก 10 ใบ ครบ 360°',
    cards: 10, price: 99, badge: 'ลึกซึ้ง',
    positions: [
      'สถานการณ์ปัจจุบัน', 'สิ่งที่ขวางกั้น', 'รากฐานของเรื่อง', 'อดีตที่ผ่านมา',
      'เป้าหมาย / สิ่งที่อาจเกิด', 'อนาคตอันใกล้', 'ตัวตนของคุณ', 'สิ่งแวดล้อมรอบตัว',
      'ความหวังและความกลัว', 'ผลลัพธ์สุดท้าย',
    ],
  ),
  Spread(
    id: 'year', name: 'พยากรณ์ 12 เดือน', desc: 'กางดวงล่วงหน้าทีละเดือนตลอดปี',
    cards: 12, price: 129, badge: 'รายปี',
    positions: [
      'เดือนที่ 1', 'เดือนที่ 2', 'เดือนที่ 3', 'เดือนที่ 4', 'เดือนที่ 5', 'เดือนที่ 6',
      'เดือนที่ 7', 'เดือนที่ 8', 'เดือนที่ 9', 'เดือนที่ 10', 'เดือนที่ 11', 'เดือนที่ 12',
    ],
  ),
];

/// All valid spread ids — used to validate a `?spread=` query param.
const spreadIds = {'three', 'single', 'love', 'career', 'decision', 'celtic', 'year'};
