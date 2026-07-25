import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'endpoints.dart';

/// ดูดวงเชิงลึก 39฿ — แพ็กเดียวกับที่ขายในเว็บ จันทรา.online และบอท FB/LINE
///
/// คำทำนายมาจาก Thaiprompt (prompt + คีย์พูลชุดเดียวกับบอท) ผ่าน juntraweb
/// แอพไม่ถือคีย์ AI และไม่มี prompt ของตัวเอง
class DeepRepository {
  DeepRepository(this._api);
  final ApiClient _api;

  /// ราคา + ยอดคงเหลือ + จำนวนคำถามสูงสุด — เรียกก่อนเปิดฟอร์ม
  Future<Map<String, dynamic>> info() async {
    final res = await _api.get<Map<String, dynamic>>(Api.deepReading);
    return _data(res);
  }

  /// สั่งทำนาย — หักเครดิตฝั่งเซิร์ฟเวอร์
  ///
  /// [idempotencyKey] ต้องส่งเสมอและใช้ค่าเดิมเมื่อกด "ลองใหม่" ข้อความเดิม
  /// เพราะ dio retry POST อัตโนมัติเมื่อ timeout/5xx — ถ้าไม่ส่ง ลูกค้าอาจ
  /// ถูกตัดเงินสองรอบจากการกดครั้งเดียว
  ///
  /// โยน ApiException: 402 เครดิตไม่พอ · 503 ระบบคำทำนายไม่พร้อม (เซิร์ฟเวอร์
  /// คืนเครดิตให้แล้ว) · 409 รายการก่อนหน้ากำลังประมวลผล
  Future<Map<String, dynamic>> create({
    required List<String> questions,
    String? birthDate,
    required String idempotencyKey,
  }) async {
    final res = await _api.post<Map<String, dynamic>>(
      Api.deepReading,
      data: {
        'questions': questions,
        if (birthDate != null && birthDate.isNotEmpty) 'birth_date': birthDate,
      },
      idempotencyKey: idempotencyKey,
    );
    return _data(res);
  }

  Map<String, dynamic> _data(Map<String, dynamic> res) {
    final inner = res['data'];
    return inner is Map<String, dynamic> ? inner : res;
  }
}

final deepRepositoryProvider = FutureProvider<DeepRepository>((ref) async {
  final api = await ref.watch(apiClientProvider.future);
  return DeepRepository(api);
});

/// ราคา/ยอดคงเหลือของแพ็กเชิงลึก — invalidate หลังสั่งทำนายเพื่อให้ยอดอัปเดต
final deepInfoProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final repo = await ref.watch(deepRepositoryProvider.future);
  return repo.info();
});

/// หมวดคำถาม 24 ข้อ — ชุดเดียวกับเว็บ ข้อมูลคงที่จึงดึงครั้งเดียวต่อรอบเปิดแอป
final chatTopicsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = await ref.watch(apiClientProvider.future);
  final res = await api.get<Map<String, dynamic>>(Api.chatTopics);
  final list = (res['data'] as List?) ?? const [];
  return list.cast<Map<String, dynamic>>();
});
