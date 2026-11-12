import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// ผลของการแตะไมค์
enum SpeechStart {
  /// เริ่มฟังแล้ว
  listening,

  /// ผู้ใช้ไม่อนุญาตไมโครโฟน
  denied,

  /// เครื่องนี้ไม่มีตัวรู้จำเสียง — ซ่อนปุ่มไมค์ไปเลย
  unavailable,

  /// ถูกหยุดก่อนเริ่มฟังเสร็จ (สลับแอพ / ปิดหน้า / แตะซ้ำ) — ไม่ใช่เครื่องใช้ไม่ได้ ห้ามซ่อนไมค์
  cancelled,
}

/// ปุ่มไมค์ในแชท — พูดแล้วได้ตัวอักษรไปวางในช่องพิมพ์ให้ลูกค้าตรวจก่อนส่ง (เหมือนเว็บ)
///
/// - ขอสิทธิ์ไมโครโฟน **ตอนแตะไมค์ครั้งแรกเท่านั้น** (`initialize` ของ speech_to_text
///   ขอสิทธิ์ทันที — ห้ามเรียกตอนเปิดหน้าแชท ไม่งั้นทุกคนโดนถามสิทธิ์ทั้งที่ไม่ได้จะพูด)
/// - ภาษาไทย (th_TH) · ไม่ส่งข้อความเอง
/// - เจ้าของหน้าจอต้องเรียก [dispose] ตอนปิดหน้า (หยุดฟังและปล่อยไมค์)
class SpeechInput {
  SpeechInput({SpeechToText? engine}) : _stt = engine ?? SpeechToText();

  final SpeechToText _stt;

  /// เครื่องนี้ใช้ไมค์ได้ไหม — null = ยังไม่รู้ (ยังไม่เคยแตะ)
  bool? available;
  bool _disposed = false;
  int _generation = 0;
  bool _starting = false;

  void Function(String text, bool isFinal)? _onText;
  VoidCallback? _onStopped;

  bool get isListening => !_disposed && _stt.isListening;

  /// ปุ่มไมค์ควรโชว์ไหม — เฉพาะมือถือ และยังไม่เคยพบว่าเครื่องนี้ไม่มีตัวรู้จำเสียง
  static bool get platformSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// เริ่มฟัง — [onText] ได้ข้อความทุกครั้งที่ตัวรู้จำเสียงอัปเดต ([isFinal] = จบประโยค)
  /// [onStopped] ถูกเรียกเมื่อหยุดฟัง (พูดจบ / หมดเวลา / error)
  Future<SpeechStart> start({
    required void Function(String text, bool isFinal) onText,
    required VoidCallback onStopped,
  }) async {
    if (_disposed || _starting) return SpeechStart.cancelled;
    final generation = ++_generation;
    _starting = true;
    try {
      _onText = onText;
      _onStopped = onStopped;

      var ok = false;
      try {
        ok = await _stt.initialize(
          onError: _handleError,
          onStatus: _handleStatus,
        );
      } catch (e) {
        if (kDebugMode) debugPrint('[Speech] init failed: $e');
        ok = false;
      }
      if (_disposed || generation != _generation) {
        return SpeechStart.cancelled;
      }
      if (!ok) {
        // init ไม่ผ่านเพราะไม่ให้สิทธิ์ ≠ เครื่องไม่มีตัวรู้จำเสียง — ไม่ให้สิทธิ์ยังกดใหม่ได้
        final permitted = await _stt.hasPermission.catchError((_) => false);
        if (_disposed || generation != _generation) {
          return SpeechStart.cancelled;
        }
        if (!permitted) return SpeechStart.denied;
        available = false;
        return SpeechStart.unavailable;
      }
      available = true;

      try {
        final locale = await _thaiLocale();
        if (_disposed || generation != _generation) {
          return SpeechStart.cancelled;
        }
        await _stt.listen(
          onResult: _handleResult,
          listenOptions: SpeechListenOptions(
            localeId: locale,
            listenMode: ListenMode.dictation,
            partialResults: true,
            cancelOnError: true,
            listenFor: const Duration(seconds: 25),
            pauseFor: const Duration(seconds: 4),
          ),
        );
      } catch (e) {
        if (kDebugMode) debugPrint('[Speech] listen failed: $e');
        return SpeechStart.unavailable;
      }
      if (_disposed || generation != _generation) {
        await _stt.cancel().catchError((_) {});
        return SpeechStart.cancelled;
      }
      return SpeechStart.listening;
    } finally {
      if (generation == _generation) _starting = false;
    }
  }

  /// หยุดฟัง (ได้ผลสุดท้ายของสิ่งที่พูดไปแล้ว)
  Future<void> stop() async {
    if (_disposed) return;
    _generation++;
    _starting = false;
    _onText = null;
    _onStopped = null;
    try {
      await _stt.cancel();
    } catch (_) {
      /* หยุดไม่ได้ก็ไม่เป็นไร */
    }
  }

  /// ปิดหน้าจอ — ยกเลิกการฟังและไม่ส่ง callback ใด ๆ อีก
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _onText = null;
    _onStopped = null;
    _stt.cancel().catchError((_) {});
  }

  Future<String?> _thaiLocale() async {
    try {
      final list = await _stt.locales();
      for (final l in list) {
        final id = l.localeId.replaceAll('-', '_').toLowerCase();
        if (id == 'th_th' || id == 'th') return l.localeId;
      }
    } catch (_) {
      /* ขอรายการภาษาไม่ได้ — ระบุไทยตรง ๆ */
    }
    return 'th_TH';
  }

  void _handleResult(SpeechRecognitionResult r) {
    if (_disposed) return;
    _onText?.call(r.recognizedWords, r.finalResult);
  }

  void _handleStatus(String status) {
    if (_disposed) return;
    if (status == SpeechToText.doneStatus ||
        status == SpeechToText.notListeningStatus) {
      _onStopped?.call();
    }
  }

  void _handleError(SpeechRecognitionError e) {
    if (kDebugMode) {
      debugPrint('[Speech] ${e.errorMsg} permanent=${e.permanent}');
    }
    if (_disposed) return;
    _onStopped?.call();
  }
}
