import 'package:flutter/material.dart';

/// Fortune categories ported from `data.jsx`. Each category seeds a
/// dedicated Spreads page (top of /spreads) and a Mae Mor system
/// prompt flavor on /chat.
class FortuneCategory {
  const FortuneCategory({
    required this.id,
    required this.name,
    required this.en,
    required this.icon,
    required this.color,
    required this.glow,
    required this.desc,
  });
  final String id;
  final String name;   // Thai
  final String en;     // English alt
  final String icon;   // Glyph (♥ ◈ ✦ ✚ ⌂ ✧ ☾ ꩜)
  final Color color;
  final Color glow;
  final String desc;
}

const fortuneCategories = <FortuneCategory>[
  FortuneCategory(
    id: 'love', name: 'ความรัก', en: 'Love', icon: '♥',
    color: Color(0xFFE91E63), glow: Color(0xFFFF6B9D),
    desc: 'คู่รัก แฟน คนพิเศษ ความสัมพันธ์',
  ),
  FortuneCategory(
    id: 'money', name: 'การเงิน', en: 'Wealth', icon: '◈',
    color: Color(0xFFFFD700), glow: Color(0xFFFFE680),
    desc: 'รายได้ การลงทุน หนี้สิน โชคทรัพย์',
  ),
  FortuneCategory(
    id: 'work', name: 'การงาน', en: 'Career', icon: '✦',
    color: Color(0xFF7C4DFF), glow: Color(0xFFB388FF),
    desc: 'อาชีพ เลื่อนตำแหน่ง ย้ายงาน',
  ),
  FortuneCategory(
    id: 'health', name: 'สุขภาพ', en: 'Health', icon: '✚',
    color: Color(0xFF00E5A0), glow: Color(0xFF69F0AE),
    desc: 'กาย ใจ พลังชีวิต',
  ),
  FortuneCategory(
    id: 'family', name: 'ครอบครัว', en: 'Family', icon: '⌂',
    color: Color(0xFFFF8A65), glow: Color(0xFFFFAB91),
    desc: 'พ่อแม่ พี่น้อง บ้าน',
  ),
  FortuneCategory(
    id: 'fortune', name: 'โชคลาภ', en: 'Luck', icon: '✧',
    color: Color(0xFFFFAB00), glow: Color(0xFFFFD740),
    desc: 'หวย ฟลุค โชคบังเอิญ',
  ),
  FortuneCategory(
    id: 'general', name: 'ภาพรวม', en: 'Overall', icon: '☾',
    color: Color(0xFFC39BD3), glow: Color(0xFFE1BEE7),
    desc: 'ดวงรวม 12 เดือนข้างหน้า',
  ),
  FortuneCategory(
    id: 'past', name: 'อดีตชาติ', en: 'Past Life', icon: '꩜',
    color: Color(0xFF9575CD), glow: Color(0xFFB39DDB),
    desc: 'กรรมเก่า ภพชาติก่อน',
  ),
];
