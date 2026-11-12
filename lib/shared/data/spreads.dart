/// Tarot spread catalog — OFFLINE FALLBACK ONLY for `GET /v1/tarot/packages`.
///
/// Kept in lock-step with juntraweb `config/tarot_spreads.php` (names, order,
/// card counts, position labels, birth flag) and `config/chat_rooms.php`
/// (which oracle reads each spread). Card counts MUST match the backend or
/// `/v1/history/readings` answers 422.
///
/// Prices here are never shown: [TarotPackage.fromLocal] drops them, so an
/// offline phone cannot advertise a price the server no longer charges.
class Spread {
  const Spread({
    required this.id,
    required this.name,
    required this.desc,
    required this.cards,
    required this.price,
    required this.room,
    this.badge,
    this.popular = false,
    this.birth = false,
    this.cooldownDays = 0,
    this.positions = const [],
  });
  final String id;
  final String name;
  final String desc;
  final int cards;
  final int price; // baht — reference only, never displayed
  /// Oracle room that reads this spread (busaba · maemor · kunsai)
  final String room;
  final String? badge;
  final bool popular;
  final bool birth;
  final int cooldownDays;
  final List<String> positions; // labels per card slot

  /// Backend `Reading.type` for this spread. The backend keys its registry
  /// by the same id, so this is always `tarot_<id>`.
  String get backendType => 'tarot_$id';
}

const spreads = <Spread>[
  Spread(
    id: 'single', name: 'ไพ่ใบเดียว', desc: 'ถามตรง ตอบตรง — พลังหลักของเรื่องนี้คืออะไร',
    cards: 1, price: 9, room: 'busaba', badge: 'เร็ว',
    positions: ['คำตอบของไพ่'],
  ),
  Spread(
    id: 'three', name: 'อดีต ปัจจุบัน อนาคต', desc: 'เห็นที่มา-ที่เป็น-ที่ไปในภาพเดียว',
    cards: 3, price: 19, room: 'busaba', popular: true,
    positions: ['อดีต', 'ปัจจุบัน', 'อนาคต'],
  ),
  Spread(
    id: 'quick', name: 'ดูไวกับน้องบุษบา', desc: 'ถามเรื่องที่ค้างใจเรื่องเดียว บุษบาตอบตรง ๆ',
    cards: 3, price: 39, room: 'busaba', birth: true,
    positions: ['เรื่องนี้ตอนนี้', 'สิ่งที่ต้องระวัง', 'ควรทำอะไรต่อ'],
  ),
  Spread(
    id: 'love', name: 'ไพ่ความรัก / เนื้อคู่', desc: 'ใจคุณ · ใจเขา · ความสัมพันธ์ · อุปสรรค · ผลลัพธ์',
    cards: 5, price: 39, room: 'busaba', badge: 'ยอดฮิต',
    positions: ['ตัวคุณ', 'อีกฝ่าย', 'ความสัมพันธ์ระหว่างกัน', 'อุปสรรค / บทเรียน', 'แนวโน้มผลลัพธ์'],
  ),
  Spread(
    id: 'career', name: 'ไพ่การงาน / การเงิน', desc: 'สถานการณ์ · จุดแข็ง · อุปสรรค · ทางออก · ผลลัพธ์',
    cards: 5, price: 39, room: 'busaba',
    positions: ['สถานการณ์ตอนนี้', 'จุดแข็ง / สิ่งที่หนุน', 'อุปสรรค / สิ่งที่ฉุด', 'สิ่งที่ควรทำ', 'แนวโน้มผลลัพธ์'],
  ),
  Spread(
    id: 'decision', name: 'ไพ่ทางแยก / ตัดสินใจ', desc: 'ชั่งสองทางเลือก เห็นสิ่งที่มองข้าม',
    cards: 5, price: 39, room: 'busaba',
    positions: ['หัวใจของเรื่อง', 'ทางเลือกที่หนึ่ง', 'ทางเลือกที่สอง', 'สิ่งที่มองข้าม', 'คำแนะนำของไพ่'],
  ),
  Spread(
    id: 'celtic', name: 'ไม้กางเขนเซลติก', desc: 'ลึก ครบ 360° ตั้งแต่รากเหง้าจนถึงผลลัพธ์',
    cards: 10, price: 99, room: 'maemor', badge: 'ลึกซึ้ง', birth: true,
    positions: [
      'สถานการณ์ปัจจุบัน', 'สิ่งที่ขวางกั้น', 'รากฐานของเรื่อง', 'อดีตที่ผ่านมา',
      'เป้าหมาย / สิ่งที่อาจเกิด', 'อนาคตอันใกล้', 'ตัวตนของคุณ', 'สิ่งแวดล้อมรอบตัว',
      'ความหวังและความกลัว', 'ผลลัพธ์สุดท้าย',
    ],
  ),
  Spread(
    id: 'year', name: 'พยากรณ์ 12 เดือน', desc: 'กางดวงล่วงหน้าทีละเดือนตลอดปี',
    cards: 12, price: 129, room: 'maemor', badge: 'รายปี', birth: true, cooldownDays: 30,
    positions: [
      'เดือนที่ 1', 'เดือนที่ 2', 'เดือนที่ 3', 'เดือนที่ 4', 'เดือนที่ 5', 'เดือนที่ 6',
      'เดือนที่ 7', 'เดือนที่ 8', 'เดือนที่ 9', 'เดือนที่ 10', 'เดือนที่ 11', 'เดือนที่ 12',
    ],
  ),
  Spread(
    id: 'kunsai', name: 'ไพ่ดูคุณไสย / โดนของ', desc: 'โดนของจริงไหม ชนิดไหน และทางแก้ที่ทำเองได้',
    cards: 10, price: 139, room: 'kunsai', birth: true,
    positions: [
      'พลังที่ครอบคุณอยู่', 'สิ่งที่มากระทบ', 'ต้นตอในอดีต', 'สิ่งที่เพิ่งผ่านมา',
      'สิ่งที่คุณกลัว/สงสัย', 'สิ่งที่กำลังจะเกิด', 'ตัวคุณเอง', 'คนรอบตัว',
      'สิ่งคุ้มครอง', 'บทสรุปและทางออก',
    ],
  ),
];

/// All valid spread ids — mirrors the backend registry keys.
const spreadIds = {
  'single', 'three', 'quick', 'love', 'career', 'decision', 'celtic', 'year', 'kunsai',
};
