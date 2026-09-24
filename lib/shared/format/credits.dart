import 'package:intl/intl.dart';

import '../../core/app_channel.dart';

/// แสดงจำนวนเครดิต (1 เครดิต = 1 บาทบนเว็บและแอพ APK)
///
/// แอพช่อง Google Play ขายแพ็กเครดิตในราคาของ Google (ตั้งใน Play Console รวมค่าธรรมเนียม)
/// ถ้ายังโชว์ค่าบริการเป็น "฿19" ลูกค้าจะเทียบกับราคาแพ็กบน Play แล้วงงว่าทำไมไม่ตรงกัน
/// จึงแสดงเป็น "19 เครดิต" — ช่อง APK เติมด้วยพร้อมเพย์แบบ 1:1 จึงคง "฿" ไว้เหมือนหน้าเว็บ
String formatCredits(num amount, {bool decimals = false}) {
  final whole = amount == amount.roundToDouble();
  final n = NumberFormat.decimalPatternDigits(
    locale: 'th',
    decimalDigits: decimals || !whole ? 2 : 0,
  ).format(amount);
  return isPlayChannel ? '$n เครดิต' : '฿$n';
}

/// ยอดเคลื่อนไหว +/− (รายการในวอลเลต)
String formatCreditsSigned(num amount) {
  final sign = amount >= 0 ? '+' : '−';
  return '$sign${formatCredits(amount.abs(), decimals: true)}';
}

/// ชื่อรายการในวอลเลต — รายการคุยกับแม่หมอรุ่นเก่าเซิร์ฟเวอร์บันทึกเป็นอังกฤษ
/// ("AI chat message") ก่อนเปลี่ยนเป็น "สนทนากับแม่หมอ" · ชื่ออื่นแสดงตามที่เซิร์ฟเวอร์ส่งมา
String walletTxLabel(String raw) => switch (raw) {
      'AI chat message' => 'สนทนากับแม่หมอ',
      _ => raw,
    };
