/// Text helpers shared by search, counters and the editor (pure Dart, tested).
library;

final _tashkeel = RegExp('[\u064B-\u065F\u0670\u06D6-\u06ED\u0640]'); // harakat, superscript alef, Quranic marks, tatweel
final _nonWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Folds Arabic spelling variants so a search finds what the user meant:
/// harakat/tatweel removed, أ إ آ ٱ → ا, ة → ه, ى → ي, ؤ → و, ئ → ي, Eastern digits → Western; Latin lower-cased.
String normalizeForSearch(String s) {
  var t = s.replaceAll(_tashkeel, '');
  final b = StringBuffer();
  for (final r in t.runes) {
    final c = switch (r) {
      0x0623 || 0x0625 || 0x0622 || 0x0671 => 0x0627,
      0x0629 => 0x0647,
      0x0649 => 0x064A,
      0x0624 => 0x0648,
      0x0626 => 0x064A,
      >= 0x0660 && <= 0x0669 => r - 0x0660 + 0x30,
      >= 0x06F0 && <= 0x06F9 => r - 0x06F0 + 0x30,
      _ => r,
    };
    b.writeCharCode(c);
  }
  t = b.toString().toLowerCase();
  return t;
}

/// Words of [s] after normalisation (letters and digits of any script).
List<String> searchTokens(String s) => normalizeForSearch(s).split(_nonWord).where((w) => w.isNotEmpty).toList();

/// An FTS5/FTS4 MATCH expression: every word must appear, each as a prefix ("مشر" finds "مشروع").
/// Returns null when the query has no searchable word.
String? ftsQuery(String q) {
  final words = searchTokens(q);
  if (words.isEmpty) return null;
  return words.map((w) => '"${w.replaceAll('"', '')}"*').join(' ');
}

/// Word count that works for Arabic and English (runs of letters/digits).
int wordCount(String s) => s.trim().isEmpty ? 0 : s.split(_nonWord).where((w) => w.isNotEmpty).length;

/// Characters excluding line breaks (what a writer means by "characters").
int charCount(String s) => s.replaceAll('\n', '').runes.length;

/// The first [n] characters of [s] on one line (previews).
String preview(String s, [int n = 140]) {
  final one = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return one.runes.length <= n ? one : '${String.fromCharCodes(one.runes.take(n))}…';
}

/// True when the text's first strong character is right-to-left (Arabic, Hebrew, Persian…).
bool isRtlText(String s) {
  for (final r in s.runes) {
    if ((r >= 0x0590 && r <= 0x08FF) || (r >= 0xFB1D && r <= 0xFEFC)) return true;
    if ((r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A) || (r >= 0xC0 && r <= 0x24F)) return false;
  }
  return false;
}

/// Human file size.
/// "1.5 MB" — wrapped in left-to-right marks so it never reads "MB 1.5" inside Arabic text.
String fileSize(int bytes) {
  final s = bytes < 1024
      ? '$bytes B'
      : bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : bytes < 1024 * 1024 * 1024
      ? '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB'
      : '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  return '\u200E$s\u200E';
}
