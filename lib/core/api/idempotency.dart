import 'dart:math' as math;

/// คีย์กันคิดเงินซ้ำสำหรับการกดหนึ่งครั้ง
///
/// ทำไมต้องมี: [ApiClient] ติด `RetryInterceptor` ไว้ ซึ่ง **retry POST เอง**
/// เมื่อ timeout หรือ 5xx ถ้าคำขอแรกไปถึงเซิร์ฟเวอร์และถูกหักเงินไปแล้ว
/// แต่คำตอบหายกลางทาง (สัญญาณมือถือไทยตกบ่อยมาก) การ retry จะกลายเป็น
/// การทำนายรอบใหม่และถูกคิดเงินซ้ำ — dio ตั้ง retries ไว้หลายรอบ
/// การกดครั้งเดียวจึงเสียเงินได้หลายเท่า
///
/// วิธีใช้ (ตรงกับที่ `deep_screen.dart` ใช้อยู่ก่อนแล้ว):
/// ```dart
/// final _attempt = IdempotentAttempt('numerology');
/// ...
/// final key = _attempt.begin();
/// try {
///   await repo.createNumerology(..., idempotencyKey: key);
///   _attempt.succeeded();            // รอบหน้าเริ่มคีย์ใหม่
/// } on ApiException catch (e) {
///   if (e.statusCode == 402 || e.statusCode == 503) _attempt.notCharged();
///   // นอกนั้นเก็บคีย์เดิมไว้ — กดลองใหม่แล้วเซิร์ฟเวอร์จะคืนผลเดิม ไม่หักซ้ำ
/// }
/// ```
///
/// **ต้องเรียก [reset] เมื่อผู้ใช้แก้ข้อมูลในฟอร์ม** ไม่งั้นคำขอใหม่ที่เนื้อหา
/// ต่างไปจะถูกส่งด้วยคีย์เดิม แล้วเซิร์ฟเวอร์คืนผลของรอบก่อนกลับมาแทน
class IdempotentAttempt {
  IdempotentAttempt(this.prefix);

  /// ใส่ไว้ให้อ่าน log ฝั่งเซิร์ฟเวอร์ออกว่าคีย์นี้มาจากหน้าไหน
  final String prefix;

  String? _key;
  String? _signature;

  /// มีการกดที่ยังไม่รู้ผลค้างอยู่ไหม
  bool get isPending => _key != null;

  /// คืนคีย์ของการกดครั้งนี้ — กดซ้ำระหว่างที่ยังไม่รู้ผลจะได้ค่าเดิมเสมอ
  ///
  /// [payload] คือลายเซ็นของข้อมูลที่จะส่ง (เช่น ชื่อ+วันเกิด) ถ้าผู้ใช้แก้
  /// ข้อมูลแล้วกดใหม่ ลายเซ็นจะเปลี่ยน → มินต์คีย์ใหม่ให้อัตโนมัติ
  /// ป้องกันกรณีที่คำขอเดิมล้มเหลว ผู้ใช้แก้ฟอร์มแล้วกดซ้ำ แต่เซิร์ฟเวอร์
  /// จำคีย์เดิมได้แล้วคืน **ผลของรอบก่อน** กลับมาแทนผลของข้อมูลใหม่
  ///
  /// ไม่ส่ง [payload] = ผู้เรียกรับผิดชอบเรียก [reset] เองเมื่อฟอร์มเปลี่ยน
  String begin([String? payload]) {
    if (payload != null && payload != _signature) {
      _key = null;
      _signature = payload;
    }
    return _key ??= _generate();
  }

  /// สำเร็จแล้ว — การกดครั้งต่อไปเป็นรายการใหม่ ต้องได้คีย์ใหม่
  void succeeded() => _key = null;

  /// ล้มเหลวแบบที่ **ยังไม่ถูกตัดเงิน** (402 เงินไม่พอ / 503 เซิร์ฟเวอร์คืนให้แล้ว)
  /// เริ่มนับใหม่ได้ ไม่ต้องกลัวว่าจะไปชนรายการเดิม
  void notCharged() => _key = null;

  /// ผู้ใช้แก้ข้อมูลในฟอร์ม — คำขอถัดไปคนละรายการกับของเดิม
  void reset() => _key = null;

  String _generate() {
    final r = math.Random();
    final tail = List.generate(6, (_) => r.nextInt(36).toRadixString(36)).join();
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$tail';
  }
}
