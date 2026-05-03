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

    return UpdateInfo(
      latestVersion: version,
      latestBuild: build,
      releaseNotesMd: (j['body'] as String? ?? '').trim(),
      apkUrl: (asset?['browser_download_url'] as String? ?? ''),
      apkSizeBytes:
          (asset?['size'] is num) ? (asset!['size'] as num).toInt() : 0,
      publishedAt: DateTime.tryParse(j['published_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [latestVersion, latestBuild, apkUrl];
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
