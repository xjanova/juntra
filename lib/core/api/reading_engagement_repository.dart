import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'api_exceptions.dart';
import 'endpoints.dart';
import 'fortune_repository.dart';

/// หลังจบคำทำนาย — แชร์ลิงก์ · รีวิว · เสียงเล่าพรีเมียม (docs/API_PARITY_2026-11.md §C3–C5)
///
/// ทุกเส้นเป็นของเจ้าของคำทำนายเท่านั้น และกติกาอยู่ฝั่งเซิร์ฟเวอร์ชุดเดียวกับเว็บ
/// (ReadingEngagementController · ReadingVoiceBuilder) — แอพแค่ส่งค่าแล้วแสดงสิ่งที่ได้กลับมา
/// เซิร์ฟเวอร์เก่าตอบ 404 ทุกเส้น หน้าจอจึงซ่อนบล็อกเหล่านี้ตาม `AppConfig.has(...)` ก่อนเรียกเสมอ
class ReadingEngagementRepository {
  ReadingEngagementRepository(this._api);
  final ApiClient _api;

  /// เปิด/ปิดลิงก์สาธารณะ — `{data: {public, url}}`
  /// ลิงก์ปิดอยู่ = คนอื่นเปิดแล้วเจอ 403 จึงต้องเปิดก่อนแชร์ทุกครั้ง
  Future<ReadingShare> setShare(int readingId, {required bool public}) async {
    final res = await _api.post<Map<String, dynamic>>(
      Api.historyReadingShare(readingId),
      data: {'public': public},
    );
    return ReadingShare.fromJson(_data(res));
  }

  /// บันทึก/แก้รีวิว — `{data: {review}}` · ข้อความผิดพลาดของช่องต่าง ๆ มาจากเซิร์ฟเวอร์
  /// (ApiClient รวม `errors.*` ให้แล้ว เช่น "เลือกจำนวนดาวก่อนนะคะ")
  Future<ReadingReview> saveReview(
    int readingId, {
    required int rating,
    String? message,
    bool allowPublic = false,
  }) async {
    final text = message?.trim() ?? '';
    final res = await _api.post<Map<String, dynamic>>(
      Api.historyReadingReview(readingId),
      data: {
        'rating': rating,
        if (text.isNotEmpty) 'message': text,
        'allow_public': allowPublic,
      },
    );
    final data = _data(res);
    final review = data['review'];
    if (review is Map) return ReadingReview.fromJson(Map<String, dynamic>.from(review));
    // เซิร์ฟเวอร์ตอบสั้น (`{ok, rating}` แบบเว็บ) — ใช้ค่าที่เพิ่งส่งไป
    return ReadingReview(rating: rating, message: text, allowPublic: allowPublic);
  }

  /// ขยับการอัดเสียงเล่า 1 ก้าว แล้วคืนสถานะล่าสุด (เว็บ `premiumVoice().tick()`)
  ///
  /// 409 = คำทำนายยังอ่านไม่เสร็จ (`wait: true`) — ไม่ใช่ข้อผิดพลาด แค่ยังไม่ถึงเวลา
  Future<VoiceBuild> voiceNext(int readingId) async {
    try {
      final res = await _api.post<Map<String, dynamic>>(Api.historyReadingVoiceNext(readingId));
      return VoiceBuild.fromJson(_data(res));
    } on ApiException catch (e) {
      if (e.statusCode == 409 && e.body != null) {
        return VoiceBuild.fromJson({..._data(e.body!), 'wait': true});
      }
      rethrow;
    }
  }

  /// ดาวน์โหลดไฟล์เสียงรวม (audio/mpeg, bearer) ลง [savePath]
  ///
  /// ใช้ dio ของ ApiClient ตัวเดิม จึงได้ bearer + X-App-Channel ครบ · ยอมรับเฉพาะ 200
  /// (ApiClient ปล่อย 4xx ผ่าน validateStatus — ถ้าไม่บังคับตรงนี้ 404 จะกลายเป็นไฟล์ JSON
  /// ชื่อ .mp3 แล้วตัวเล่นพังเงียบ ๆ)
  Future<void> downloadVoice(int readingId, String savePath, {String? url, CancelToken? cancel}) async {
    try {
      await _api.dio.download(
        _voiceUrl(readingId, url),
        savePath,
        cancelToken: cancel,
        options: Options(
          validateStatus: (s) => s == 200,
          receiveTimeout: const Duration(seconds: 90),
          headers: {'Accept': 'audio/mpeg'},
        ),
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  /// URL ของไฟล์เสียง — ใช้ของที่เซิร์ฟเวอร์ให้มาได้เฉพาะเมื่ออยู่บนโฮสต์ API เดียวกัน
  /// (bearer ของลูกค้าต้องไม่หลุดไปโฮสต์อื่น) · นอกนั้นใช้เส้นมาตรฐานของสัญญา
  String _voiceUrl(int readingId, String? url) {
    if (url != null && url.startsWith('https://')) {
      final base = Uri.tryParse(_api.dio.options.baseUrl);
      final u = Uri.tryParse(url);
      if (base != null && u != null && u.host == base.host && u.path.contains('/v1/history/readings/$readingId/voice')) {
        return url;
      }
    }
    return Api.historyReadingVoiceFile(readingId);
  }

  static Map<String, dynamic> _data(Map<String, dynamic> res) {
    final d = res['data'];
    return d is Map ? Map<String, dynamic>.from(d) : res;
  }
}

/// สถานะการอัดเสียงเล่า — ชุดเดียวกับ `ReadingVoiceBuilder::view()` ของเว็บ
/// `{status: building|ready|partial|none, done, total, refunded}` (+ `wait` / `busy`)
@immutable
class VoiceBuild {
  const VoiceBuild({
    required this.status,
    this.done = 0,
    this.total = 0,
    this.refunded = false,
    this.wait = false,
    this.busy = false,
    this.url,
    this.voice,
  });

  final String status;
  final int done;
  final int total;

  /// ไม่ได้เสียงเลยสักบท → เซิร์ฟเวอร์คืนค่าพรีเมียมให้แล้ว
  final bool refunded;

  /// คำทำนายยังอ่านไม่เสร็จ (409) — รอแล้วถามใหม่
  final bool wait;

  /// อีกเครื่อง/อีกแท็บกำลังขยับอยู่ — ได้สถานะปัจจุบันกลับมาเฉย ๆ
  final bool busy;

  /// ลิงก์ไฟล์เสียงที่เซิร์ฟเวอร์ให้มา (ถ้ามี)
  final String? url;

  /// บทเล่า + เวลา (ถ้าเซิร์ฟเวอร์แนบมาด้วยตอนเสร็จ)
  final ReadingVoice? voice;

  bool get building => status == 'building';
  bool get ready => status == 'ready' || status == 'partial';
  bool get none => status == 'none';

  /// 0..1 สำหรับแถบความคืบหน้า
  double get progress => total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;

  factory VoiceBuild.fromJson(Map<String, dynamic> j) {
    final voice = j['voice'];
    return VoiceBuild(
      status: (j['status'] is String && (j['status'] as String).isNotEmpty) ? j['status'] as String : 'none',
      done: (j['done'] as num?)?.toInt() ?? 0,
      total: (j['total'] as num?)?.toInt() ?? 0,
      refunded: j['refunded'] == true,
      wait: j['wait'] == true,
      busy: j['busy'] == true,
      url: j['url'] is String ? j['url'] as String : null,
      voice: voice is Map ? ReadingVoice.fromJson(Map<String, dynamic>.from(voice)) : null,
    );
  }
}

final readingEngagementRepositoryProvider = FutureProvider<ReadingEngagementRepository>((ref) async {
  final api = await ref.watch(apiClientProvider.future);
  return ReadingEngagementRepository(api);
});
