import 'package:flutter/foundation.dart';

import '../../core/api/fortune_repository.dart';

/// หน้าแรกของเว็บ (punycode ของ จันทรา.online — ชุดเดียวกับ ApiClient)
const kSiteUrl = 'https://xn--82c4af5bzdj.online';

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
/// - คำทำนายที่เปิดสาธารณะแล้ว → ลิงก์หน้าผลที่เซิร์ฟเวอร์ให้
/// - ไม่มีลิงก์ที่เปิดได้ (รวมเซิร์ฟเวอร์เก่า) → ข้อความอย่างเดียว
ShareLink shareLinkFor({required int? readingId, ReadingShare? share}) {
  if (readingId == null) return const ShareLink(url: kSiteUrl);
  if (share == null || !share.public) return const ShareLink();
  final uri = Uri.tryParse(share.url ?? '');
  if (uri == null || uri.scheme != 'https' || uri.host != Uri.parse(kSiteUrl).host ||
      uri.userInfo.isNotEmpty || uri.port != 443 || uri.path != '/tarot/result/$readingId') {
    return const ShareLink();
  }
  return ShareLink(url: uri.toString(), readingLink: true);
}

/// ข้อความที่แชร์ — ชื่อผู้อ่านตามห้อง (เว็บเลิกพูดแทนว่า "แม่หมอ" ทุกห้องแล้ว)
String shareMessage({int? readingId, String reader = 'แม่หมอจันทรา'}) => readingId == null
    ? 'ดูดวงไพ่ทาโรต์กับแม่หมอจันทรา ✨ ลองดูดวงกันไหม'
    : '$readerเปิดไพ่ให้ฉันแล้ว ✨ ลองดูดวงกันไหม';
