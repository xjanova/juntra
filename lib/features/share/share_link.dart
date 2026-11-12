import 'package:flutter/foundation.dart';

import '../../core/api/fortune_repository.dart';

/// หน้าแรกของเว็บ (punycode ของ จันทรา.online — ชุดเดียวกับ ApiClient)
const kSiteUrl = 'https://xn--82c4af5bzdj.online';

/// ลิงก์หน้าผลบนเว็บรุ่นก่อนสัญญาใหม่ — เปิดได้เฉพาะคำทำนายที่เจ้าของเปิดแชร์ไว้แล้ว
/// (ปิดอยู่ = คนอื่นเปิดเจอ 403)
String legacyReadingUrl(int readingId) => '$kSiteUrl/tarot/result/$readingId';

/// สิ่งที่จะส่งออกไปเมื่อกดแชร์
@immutable
class ShareLink {
  const ShareLink({this.url, this.readingLink = false});

  /// ลิงก์ที่ใส่ในข้อความ — null = แชร์ข้อความอย่างเดียว (ดีกว่าลิงก์ที่เปิดแล้วเจอ 403)
  final String? url;

  /// ลิงก์ชี้ไปที่คำทำนายนี้ (ไม่ใช่แค่หน้าแรก)
  final bool readingLink;

  bool get hasUrl => url != null;
}

/// ตัดสินว่าแชร์อะไรได้จริง
///
/// - ไม่มีคำทำนาย (แชร์จากหน้าแพ็กเกจ) → หน้าแรกของเว็บ
/// - คำทำนายที่เปิดสาธารณะแล้ว → ลิงก์ที่เซิร์ฟเวอร์ให้ (ไม่มี = รูปแบบลิงก์เดิมของเว็บ)
/// - ยังเป็นส่วนตัว (เซิร์ฟเวอร์เก่าที่เปิดแชร์จากแอพไม่ได้) → ข้อความอย่างเดียว ไม่มีลิงก์
ShareLink shareLinkFor({required int? readingId, ReadingShare? share}) {
  if (readingId == null) return const ShareLink(url: kSiteUrl);
  if (share == null || !share.public) return const ShareLink();
  return ShareLink(url: share.url ?? legacyReadingUrl(readingId), readingLink: true);
}

/// ข้อความที่แชร์ — ชื่อผู้อ่านตามห้อง (เว็บเลิกพูดแทนว่า "แม่หมอ" ทุกห้องแล้ว)
String shareMessage({int? readingId, String reader = 'แม่หมอจันทรา'}) => readingId == null
    ? 'ดูดวงไพ่ทาโรต์กับแม่หมอจันทรา ✨ ลองดูดวงกันไหม'
    : '$readerเปิดไพ่ให้ฉันแล้ว ✨ ลองดูดวงกันไหม';
