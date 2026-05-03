/// 22 Major Arcana ported from `extracted/juntra/project/data.jsx`.
///
/// Suit cards (Cups/Pentacles/Swords/Wands × 14) will be filled by the
/// backend via `/v1/fortune/cards` once the deck SVGs are commissioned;
/// the cinematic shuffle currently fans the 22 majors only and the
/// remaining 56 are face-down generic backs.
class TarotCard {
  const TarotCard({
    required this.id,
    required this.name,
    required this.thai,
    required this.meaning,
    required this.element,
    required this.symbol,
  });
  final int id;
  final String name;       // English Rider-Waite name
  final String thai;       // Thai translation
  final String meaning;    // Short upright meaning (Thai)
  final String element;    // Astrological glyph / element
  final String symbol;     // Roman numeral
}

const tarotDeck = <TarotCard>[
  TarotCard(id: 0, name: 'The Fool', thai: 'คนโง่',
    meaning: 'การเริ่มต้นใหม่ ความกล้าหาญ การก้าวออกจากกรอบ',
    element: '☉', symbol: '0'),
  TarotCard(id: 1, name: 'The Magician', thai: 'นักมายากล',
    meaning: 'พลังในการสร้างสรรค์ ความสามารถในการเปลี่ยนแปลงชะตา',
    element: '☿', symbol: 'I'),
  TarotCard(id: 2, name: 'The High Priestess', thai: 'นักบวชหญิง',
    meaning: 'สัญชาตญาณลึกซึ้ง ความลับที่กำลังเปิดเผย',
    element: '☽', symbol: 'II'),
  TarotCard(id: 3, name: 'The Empress', thai: 'จักรพรรดินี',
    meaning: 'ความอุดมสมบูรณ์ ความรักและการให้กำเนิด',
    element: '♀', symbol: 'III'),
  TarotCard(id: 4, name: 'The Emperor', thai: 'จักรพรรดิ',
    meaning: 'อำนาจ การควบคุม ความมั่นคง',
    element: '♈', symbol: 'IV'),
  TarotCard(id: 5, name: 'The Hierophant', thai: 'พระสันตะปาปา',
    meaning: 'ภูมิปัญญา การชี้นำจากครูบาอาจารย์',
    element: '♉', symbol: 'V'),
  TarotCard(id: 6, name: 'The Lovers', thai: 'คู่รัก',
    meaning: 'ความรัก การเลือกของหัวใจ ความผูกพัน',
    element: '♊', symbol: 'VI'),
  TarotCard(id: 7, name: 'The Chariot', thai: 'รถม้าศึก',
    meaning: 'ชัยชนะ ความมุ่งมั่น เดินทางไกล',
    element: '♋', symbol: 'VII'),
  TarotCard(id: 8, name: 'Strength', thai: 'พลัง',
    meaning: 'ความเข้มแข็งภายใน ความอดทน',
    element: '♌', symbol: 'VIII'),
  TarotCard(id: 9, name: 'The Hermit', thai: 'ฤๅษี',
    meaning: 'การค้นหาตนเอง ความสันโดษอันมีคุณค่า',
    element: '♍', symbol: 'IX'),
  TarotCard(id: 10, name: 'Wheel of Fortune', thai: 'วงล้อโชคชะตา',
    meaning: 'การเปลี่ยนแปลง โชคลาภหมุนเวียน',
    element: '♃', symbol: 'X'),
  TarotCard(id: 11, name: 'Justice', thai: 'ความยุติธรรม',
    meaning: 'ความถูกต้อง ผลแห่งกรรม การตัดสินใจ',
    element: '♎', symbol: 'XI'),
  TarotCard(id: 12, name: 'The Hanged Man', thai: 'คนแขวนคอ',
    meaning: 'การมองสิ่งต่างๆ จากมุมใหม่ การเสียสละ',
    element: '♆', symbol: 'XII'),
  TarotCard(id: 13, name: 'Death', thai: 'ความตาย',
    meaning: 'การสิ้นสุดเพื่อเริ่มต้นใหม่ การเปลี่ยนผ่าน',
    element: '♏', symbol: 'XIII'),
  TarotCard(id: 14, name: 'Temperance', thai: 'ความพอดี',
    meaning: 'ความสมดุล การประนีประนอม',
    element: '♐', symbol: 'XIV'),
  TarotCard(id: 15, name: 'The Devil', thai: 'ปีศาจ',
    meaning: 'พันธนาการ ความหลงใหล สิ่งที่ฉุดรั้ง',
    element: '♑', symbol: 'XV'),
  TarotCard(id: 16, name: 'The Tower', thai: 'หอคอย',
    meaning: 'การเปลี่ยนแปลงครั้งใหญ่ การปลดปล่อย',
    element: '♂', symbol: 'XVI'),
  TarotCard(id: 17, name: 'The Star', thai: 'ดวงดาว',
    meaning: 'ความหวัง แรงบันดาลใจ พรที่กำลังมา',
    element: '♒', symbol: 'XVII'),
  TarotCard(id: 18, name: 'The Moon', thai: 'พระจันทร์',
    meaning: 'ความฝัน ความลึกลับ สัญชาตญาณนำทาง',
    element: '♓', symbol: 'XVIII'),
  TarotCard(id: 19, name: 'The Sun', thai: 'พระอาทิตย์',
    meaning: 'ความสุข ความสำเร็จ ชีวิตที่สดใส',
    element: '☉', symbol: 'XIX'),
  TarotCard(id: 20, name: 'Judgement', thai: 'การพิพากษา',
    meaning: 'การตื่นรู้ การเรียกร้องของจิตวิญญาณ',
    element: '♇', symbol: 'XX'),
  TarotCard(id: 21, name: 'The World', thai: 'โลก',
    meaning: 'ความสมบูรณ์ การบรรลุเป้าหมาย',
    element: '♄', symbol: 'XXI'),
];
