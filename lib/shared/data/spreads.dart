/// Tarot spread definitions ported from `data.jsx`.
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
  final int price; // baht
  final String? badge;
  final bool popular;
  final List<String> positions; // labels per card slot
}

const spreads = <Spread>[
  Spread(
    id: '3card', name: '3 ใบ', desc: 'อดีต · ปัจจุบัน · อนาคต',
    cards: 3, price: 0, badge: 'ฟรี', popular: true,
    positions: ['อดีต', 'ปัจจุบัน', 'อนาคต'],
  ),
  Spread(
    id: 'love', name: 'ผังคู่รัก', desc: 'ใจฉัน · ใจเขา · ความสัมพันธ์ · ผลลัพธ์',
    cards: 4, price: 49,
    positions: ['ใจฉัน', 'ใจเขา', 'ความสัมพันธ์', 'ผลลัพธ์'],
  ),
  Spread(
    id: 'celtic', name: 'เซลติกครอส', desc: 'การวิเคราะห์เชิงลึก 10 ใบ',
    cards: 10, price: 199, badge: 'ลึกซึ้ง',
    positions: [
      'แก่นสถานการณ์', 'อุปสรรค', 'ราก-จิตใต้สำนึก', 'อดีตล่าสุด',
      'เป้าหมาย-สติ', 'อนาคตใกล้', 'ตัวเอง', 'สิ่งแวดล้อม',
      'ความหวัง-ความกลัว', 'ผลลัพธ์',
    ],
  ),
  Spread(
    id: 'year', name: 'ดวง 12 เดือน', desc: 'พยากรณ์รายเดือนตลอดปี',
    cards: 12, price: 299, badge: 'ใหม่',
    positions: [
      'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
      'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
    ],
  ),
  Spread(
    id: 'horseshoe', name: 'เกือกม้า', desc: '7 ใบ ครอบคลุมทุกแง่มุม',
    cards: 7, price: 99,
    positions: [
      'อดีต', 'ปัจจุบัน', 'อิทธิพลซ่อน', 'คำแนะนำ',
      'สิ่งแวดล้อม', 'อุปสรรค', 'ผลลัพธ์',
    ],
  ),
  Spread(
    id: 'yes-no', name: 'ใช่ / ไม่ใช่', desc: 'ใบเดียว ตอบคำถามเร่งด่วน',
    cards: 1, price: 19,
    positions: ['คำตอบ'],
  ),
];
