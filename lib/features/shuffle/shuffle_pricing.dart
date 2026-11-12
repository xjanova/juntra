import '../../core/api/app_config_repository.dart';
import '../../shared/format/credits.dart';

/// ป้ายตัวเลือกเสียงพรีเมียมบนแถบยืนยัน — รูปแบบราคาเดียวกับราคาอื่นในจอ (formatCredits)
String voicePremiumLabel(VoicePremiumOffer offer) =>
    'เสียงอ่านคำทำนาย + ถามต่อ ${offer.qaMinutes} นาที · +${formatCredits(offer.price)}';

/// ยอดที่จะถูกหักจริง — ค่าไพ่ + ค่าเสียง (ถ้าเลือก) · ไม่รู้ราคาไพ่ (ออฟไลน์) = null
num? confirmTotal({num? price, VoicePremiumOffer? premium, bool premiumOn = false}) {
  final extra = (premiumOn && premium != null) ? premium.price : 0;
  if (price == null) return extra > 0 ? extra : null;
  return price + extra;
}

/// ท้ายปุ่ม "เปิดไพ่" — " · 39 เครดิต" / " · ฟรี" / "" (ไม่รู้ราคา)
///
/// ไม่รู้ราคาไพ่แต่เลือกเสียง → บอกเฉพาะส่วนที่รู้ ("+100 เครดิต") ไม่เดายอดรวม
String confirmPriceSuffix({num? price, VoicePremiumOffer? premium, bool premiumOn = false}) {
  final extra = premiumOn ? premium : null;
  if (price == null) return extra != null ? ' · +${formatCredits(extra.price)}' : '';
  final total = confirmTotal(price: price, premium: premium, premiumOn: premiumOn)!;
  return total <= 0 ? ' · ฟรี' : ' · ${formatCredits(total)}';
}
