/// One-line preview of a reading for list rows (home, history).
///
/// Readings are markdown (`## 🎯 ฟันธง`, bullets, tables); a raw slice of that
/// shows "## 🎯 ฟันธง" instead of the answer. This keeps the prose lines only:
/// headings, table rows and rules go, bullet/quote/number markers and
/// emphasis marks are stripped. The server already sends plain text — this
/// keeps an older server (or an old reading) tidy too, and is a no-op on plain
/// text.
String plainPreview(String raw) {
  final prose = <String>[];
  final headings = <String>[];
  for (var line in raw.split(RegExp(r'\r?\n'))) {
    line = line.trim();
    if (line.isEmpty || line.startsWith('|') || _rule.hasMatch(line)) continue;
    if (line.startsWith('#')) {
      headings.add(line.replaceFirst(RegExp(r'^#+\s*'), ''));
      continue;
    }
    line = line.replaceFirst(_marker, '').replaceAll(_emphasis, '').trim();
    if (line.isNotEmpty) prose.add(line);
  }
  // A slice that holds only headings still says something ("ฟันธง")
  return (prose.isNotEmpty ? prose : headings).join(' ');
}

final _rule = RegExp(r'^[-*_]{3,}$');
final _marker = RegExp(r'^(?:[-*+>]\s+|\d+[.)]\s+)');
final _emphasis = RegExp(r'\*\*|__|`');
