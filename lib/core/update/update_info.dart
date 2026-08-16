import 'package:equatable/equatable.dart';

/// Metadata about the latest release available for download.
///
/// Constructed from the GitHub Releases API response — kept opaque to
/// the UI: dialogs render `latestVersion` + `releaseNotesMd` only, never
/// exposing the upstream provider name or URLs.
class UpdateInfo extends Equatable {
  const UpdateInfo({
    required this.latestVersion,
    required this.latestBuild,
    required this.releaseNotesMd,
    required this.apkUrl,
    required this.apkSizeBytes,
    required this.publishedAt,
    this.apkSha256 = '',
  });

  /// Semver string like "1.0.3" (the tag without leading "v" or "+build")
  final String latestVersion;

  /// Android versionCode = the "+N" suffix on the tag (vX.Y.Z+N)
  final int latestBuild;

  /// Markdown-formatted changelog shown in the update sheet.
  final String releaseNotesMd;

  /// Direct APK download URL — internal use only, never rendered.
  final String apkUrl;

  final int apkSizeBytes;
  final DateTime publishedAt;

  /// Lowercase hex SHA-256 of the APK asset, from the GitHub asset `digest`
  /// field (`sha256:<hex>`). Empty when the release predates digest support;
  /// callers then skip verification rather than block the install.
  final String apkSha256;

  /// Parse the GitHub Releases API JSON response.
  ///
  /// Tag format: `v0.1.0+1` → version=0.1.0, build=1
  /// Picks the universal APK by default; falls back to arm64-v8a then
  /// the first .apk asset in the release.
  factory UpdateInfo.fromGitHubRelease(Map<String, dynamic> j) {
    final tag = (j['tag_name'] as String? ?? 'v0.0.0+0').replaceFirst('v', '');
    final parts = tag.split('+');
    final version = parts.first;
    final build = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

    final assets = (j['assets'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    Map<String, dynamic>? pick(bool Function(String) match) {
      for (final a in assets) {
        final name = (a['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('.apk') && match(name)) return a;
      }
      return null;
    }

    final asset = pick((n) => n.contains('universal')) ??
        pick((n) => n.contains('arm64')) ??
        pick((n) => true);

    // GitHub returns `digest: "sha256:<hex>"` on assets uploaded via the API.
    final rawDigest = (asset?['digest'] as String? ?? '').trim();
    final sha = rawDigest.startsWith('sha256:')
        ? rawDigest.substring('sha256:'.length).toLowerCase()
        : '';

    return UpdateInfo(
      latestVersion: version,
      latestBuild: build,
      // 🔴 ห้ามส่ง body ดิบเข้า UI เด็ดขาด
      //
      // GitHub เขียนบันทึกรุ่นให้อัตโนมัติ และมี URL ของตัวเองติดมาเสมอ:
      //   * <หัวข้อ> by @user in https://github.com/xjanova/juntra/pull/10
      //   **Full Changelog**: https://github.com/.../compare/v0.3.4+15...v0.3.5+16
      // ของเดิมส่งตรงเข้า MarkdownBody ผู้ใช้จึงเห็น github.com เต็ม ๆ สองบรรทัด
      // ผิดสัญญาที่ทั้งไฟล์นี้และ update_service.dart เขียนไว้เองว่าจะไม่เปิดเผย
      // ผู้ให้บริการเบื้องหลัง (ผู้ใช้ต้องเห็นแค่คำว่า "เซิร์ฟเวอร์อัปเดต")
      releaseNotesMd: sanitizeReleaseNotes(j['body'] as String? ?? ''),
      apkUrl: (asset?['browser_download_url'] as String? ?? ''),
      apkSizeBytes:
          (asset?['size'] is num) ? (asset!['size'] as num).toInt() : 0,
      publishedAt: DateTime.tryParse(j['published_at']?.toString() ?? '') ??
          DateTime.now(),
      apkSha256: sha,
    );
  }

  @override
  // Intentionally exclude apkUrl from props/toString. UpdateInfo equality
  // is keyed by (version, build) — those uniquely identify a release.
  // Keeping apkUrl out means an accidental `print(updateInfo)` or any crash
  // reporter that serializes Equatable.toString() can't leak the upstream
  // GitHub URL into logs (UI separation contract — see update_service.dart).
  List<Object?> get props => [latestVersion, latestBuild];

  @override
  String toString() => 'UpdateInfo($latestVersion+$latestBuild)';
}

/// ล้างบันทึกรุ่นให้ไม่มีร่องรอยของผู้ให้บริการเบื้องหลัง
///
/// สัญญาของระบบอัปเดต: ผู้ใช้ต้องเห็นแค่ "เซิร์ฟเวอร์อัปเดต" — ห้ามเห็นชื่อ
/// หรือ URL ของที่เก็บไฟล์เด็ดขาด แต่ GitHub ใส่ลิงก์ของตัวเองมาในบันทึกรุ่น
/// อัตโนมัติทุกครั้ง (`by @user in https://github.com/...`,
/// `**Full Changelog**: https://github.com/...`) ถ้าไม่ล้างก่อน ข้อความพวกนี้
/// จะไปโผล่กลางหน้าต่างอัปเดตทั้งดุ้น
///
/// ล้างแบบ "ตัดทุก URL ทิ้ง" ไม่ใช่ตัดเฉพาะที่มีคำว่า github เพราะ
/// 1) ลิงก์ในบันทึกรุ่นกดไม่ได้อยู่แล้ว (`onTapLink` ถูกปิดไว้) โชว์ไปก็ไร้ค่า
/// 2) โดเมนอื่นในอนาคต (เช่น มิเรอร์) ก็ไม่ควรหลุดออกไปเหมือนกัน
String sanitizeReleaseNotes(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return '';

  // 1) ลิงก์แบบ markdown [ป้าย](url) → เหลือแค่ป้าย
  text = text.replaceAllMapped(
    RegExp(r'\[([^\]]*)\]\(\s*<?https?://[^)\s]+>?\s*\)'),
    (m) => m[1] ?? '',
  );

  // 2) หาง " by @user in <url>" ที่ GitHub ต่อท้ายทุกบรรทัดของ What's Changed
  text = text.replaceAll(
    RegExp(r'\s+by\s+@[\w-]+\s+in\s+\S*', caseSensitive: false),
    '',
  );

  // 3) URL เปลือย ๆ ที่เหลือ
  text = text.replaceAll(RegExp(r'<?https?://\S+>?'), '');

  // 4) ตัดบรรทัดที่เหลือแต่หัวข้อว่าง ๆ หลังลบลิงก์ออก
  //    (เช่น "**Full Changelog**:" ที่เนื้อหาคือ URL ล้วน)
  final kept = <String>[];
  for (final line in text.split('\n')) {
    final t = line.trim();
    // บรรทัดที่เหลือแต่เครื่องหมายวรรคตอน/มาร์กอัป = ขยะจากการลบ URL
    final stripped = t.replaceAll(RegExp(r'[*_`#>\-•:\s]'), '');

    // ป้ายกำกับที่เนื้อหาเป็น URL ล้วน — พอลบ URL แล้วเหลือแต่ "หัวข้อ:"
    // ลอย ๆ (เช่น `**Full Changelog**:`) ต้องตัดทั้งบรรทัด ไม่ใช่ปล่อยค้าง
    final danglingLabel = t.endsWith(':');

    if (t.isEmpty || stripped.isEmpty || danglingLabel) {
      // เก็บบรรทัดว่างไว้คั่นย่อหน้า แต่ไม่ให้ซ้อนกันเกินหนึ่ง
      if (kept.isNotEmpty && kept.last.isNotEmpty) kept.add('');
      continue;
    }
    // กันคำว่า github/gh หลุดในเนื้อความ (บางคนพิมพ์เอง)
    if (RegExp(r'github', caseSensitive: false).hasMatch(t)) continue;
    kept.add(line.trimRight());
  }

  while (kept.isNotEmpty && kept.last.isEmpty) {
    kept.removeLast();
  }

  return kept.join('\n').trim();
}

/// Compare two semver strings. Returns:
///   -1 if a < b,  0 if equal,  1 if a > b
/// Pre-release suffixes are stripped before comparison.
int compareSemver(String a, String b) {
  List<int> parse(String v) =>
      v.split('-').first.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  final pa = parse(a);
  final pb = parse(b);
  final len = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < len; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x < y ? -1 : 1;
  }
  return 0;
}

/// True if (newVersion, newBuild) is strictly newer than (curVersion,
/// curBuild): the semver dominates; the build number breaks a version tie.
/// This is what catches `release:build` bumps — same X.Y.Z, higher +build —
/// which a version-only compare would silently report as up-to-date.
bool isReleaseNewer(
    String curVersion, int curBuild, String newVersion, int newBuild) {
  final cmp = compareSemver(curVersion, newVersion);
  if (cmp != 0) return cmp < 0;
  return newBuild > curBuild;
}
