import 'package:flutter/painting.dart';

import '../../core/api/rooms_repository.dart';
import '../../core/api/tarot_packages_repository.dart';

/// แพ็กเกจของผู้อ่านหนึ่งคน — หัวกลุ่ม "อ่านโดย …" บนหน้าแพ็กเกจ
class ReaderGroup {
  const ReaderGroup({required this.roomKey, required this.readerName, required this.accent, required this.packages});
  final String roomKey;
  final String readerName;
  final Color accent;
  final List<TarotPackage> packages;
}

/// ชื่อผู้อ่านของแพ็กเกจ (เว็บ `ChatRooms::readerName`) — ห้องแม่หมอใช้ชื่อสั้น "แม่หมอ"
String readerNameOf(TarotPackage p) {
  final n = p.readerName;
  if (n != null && n.isNotEmpty) return n;
  final room = OracleRoom.builtIn(p.roomKey);
  return room.key == OracleRoom.defaultKey ? room.short : room.name;
}

/// จัดแพ็กเกจเป็นกลุ่มตามผู้อ่าน เรียงแบบเว็บ
///
/// เว็บเลิกมีหน้ารวมไพ่แล้ว (/tarot พาเข้าเมนูในห้องผู้พยากรณ์) ลำดับจึงตามห้อง
/// (`ChatRooms::all()` — ถูก → แพง: บุษบา · แม่หมอ · คุณไสย) และในห้องตามรายการ
/// `spreads` ของห้องนั้น (แพ็กเกจประจำห้องขึ้นก่อน) · แพ็กเกจที่ห้องไม่ได้ระบุต่อท้ายตามลำดับเซิร์ฟเวอร์
///
/// `web_only` ไม่แสดงในแอพ — ขายเฉพาะทางห้องแชทบนเว็บ (และช่อง Play ห้ามพาไปจ่ายนอกแอพ)
List<ReaderGroup> groupByReader(List<TarotPackage> all, RoomsState rooms) {
  final visible = all.where((p) => !p.webOnly).toList();
  final roomOrder = <String>[
    for (final r in rooms.rooms) r.key,
    for (final k in OracleRoom.keys)
      if (!rooms.rooms.any((r) => r.key == k)) k,
  ];
  final groups = <ReaderGroup>[];
  for (final key in roomOrder) {
    final mine = visible.where((p) => OracleRoom.normalize(p.roomKey) == key).toList();
    if (mine.isEmpty) continue;
    final order = rooms.room(key).spreads;
    int rank(TarotPackage p) {
      final i = order.indexOf(p.key);
      return i < 0 ? order.length + visible.indexOf(p) : i;
    }

    mine.sort((a, b) => rank(a).compareTo(rank(b)));
    groups.add(ReaderGroup(
      roomKey: key,
      readerName: readerNameOf(mine.first),
      accent: OracleRoom.builtIn(key).accent,
      packages: mine,
    ));
  }
  return groups;
}

/// เซิร์ฟเวอร์บอกห้องของแพ็กเกจมาแล้ว (สัญญา B) — เซิร์ฟเวอร์เก่าไม่บอก = รายการเดียวแบบเดิม ไม่มีหัวกลุ่ม
bool hasReaderInfo(List<TarotPackage> all) => all.any((p) => p.room != null);
