/// Pure logic of word search (docs/book-search.md): user input → FTS5 MATCH
/// expression, match locations in the text, and snippets. Used by the repository
/// (snippets) and the reader (inline highlight).
library;

/// Minimum letters/digits before a search runs.
const bookSearchMinChars = 2;

/// Maximum number of results shown.
const bookSearchMaxHits = 500;

/// Search history size per book.
const bookSearchMaxRecents = 5;

/// Context length on each side of the match in a snippet.
const bookSearchSnippetContext = 60;

/// `settings` key for one book's search history (included in backups).
String bookSearchRecentKey(int bookId) => 'search.recent.$bookId';

/// One `[start, end)` range in the original text.
typedef TextRange = ({int start, int end});

/// A validated query: [match] is safe to use in `MATCH`; [ranges] finds the same
/// words in the text for snippets and highlights.
class BookSearchQuery {
  const BookSearchQuery._(this.words);

  /// Folded words (lowercase, accents removed), in input order.
  final List<String> words;

  /// Null when the input has fewer than [bookSearchMinChars] letters/digits.
  ///
  /// Several words form a phrase (in order) and the last word is a prefix:
  /// `netherfield par` finds "Netherfield Park". Word separators: anything but
  /// letters/digits, including straight and curly quotes, so `don’t` = `don't`
  /// (same as the unicode61 tokenizer in the index).
  static BookSearchQuery? parse(String input) {
    final words = _words(fold(input)).map((w) => w.text).toList();
    final letters = words.fold<int>(0, (n, w) => n + w.length);
    if (letters < bookSearchMinChars) return null;
    return BookSearchQuery._(words);
  }

  /// FTS5 expression: `"netherfield par"*`. Words are split at non-letters/digits,
  /// so `"`, `*`, `-`, `OR`, `NEAR` from the user never become syntax.
  String get match => '"${words.join(' ')}"*';

  /// Range of each occurrence of the phrase in [text] (whole words; the last word
  /// may continue to the end of the word, like a prefix in the index). Sorted, non-overlapping.
  List<TextRange> ranges(String text) {
    final found = _words(fold(text));
    final last = words.length - 1;
    final out = <TextRange>[];
    for (var i = 0; i + last < found.length; i++) {
      var ok = true;
      for (var j = 0; j < last && ok; j++) {
        ok = found[i + j].text == words[j];
      }
      if (ok && found[i + last].text.startsWith(words[last])) {
        out.add((start: found[i].start, end: found[i + last].end));
        i += last; // skip overlapping matches
      }
    }
    return out;
  }
}

/// A short text around the first occurrence + the match position inside it.
typedef BookSearchSnippet = ({String text, int matchStart, int matchEnd});

/// [bookSearchSnippetContext] characters on each side of [match], cut with "…" on
/// the side that was truncated. Without [match] (not found in the text): the start of the paragraph.
BookSearchSnippet bookSearchSnippet(String text, TextRange? match) {
  const ctx = bookSearchSnippetContext;
  if (match == null) {
    final cut = text.length > ctx * 2;
    return (
      text: cut ? '${text.substring(0, ctx * 2).trimRight()}…' : text,
      matchStart: 0,
      matchEnd: 0,
    );
  }
  var from = match.start - ctx;
  var to = match.end + ctx;
  final head = from > 0;
  final tail = to < text.length;
  if (!head) from = 0;
  if (!tail) to = text.length;
  final prefix = head ? '…' : '';
  final body = text.substring(from, to);
  final lead = body.length - body.trimLeft().length;
  final trimmed = body.trim();
  final offset = prefix.length - lead - from;
  return (
    text: '$prefix$trimmed${tail ? '…' : ''}',
    matchStart: match.start + offset,
    matchEnd: match.end + offset,
  );
}

final _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);

List<({String text, int start, int end})> _words(String folded) => [
  for (final m in _word.allMatches(folded))
    (text: m.group(0)!, start: m.start, end: m.end),
];

/// Lowercases and strips accents while keeping the input length (match indices
/// stay valid in the original text). Enough for Latin; other scripts are only lowercased.
String fold(String s) {
  final b = StringBuffer();
  for (final unit in s.runes) {
    final c = String.fromCharCode(unit);
    b.write(_accents[c] ?? c.toLowerCase());
  }
  final out = b.toString();
  // Lowercasing can change the length (e.g. "İ"): if so, don't trust its
  // indices; use the non-lowercased version for the characters that changed.
  return out.length == s.length ? out : s;
}

final _accents = <String, String>{
  for (final e in _pairs.entries)
    for (final ch in e.value.split('')) ch: e.key,
};

const _pairs = <String, String>{
  'a': 'àáâãäåāăąÀÁÂÃÄÅĀĂĄ',
  'c': 'çćĉċčÇĆĈĊČ',
  'd': 'ďđĎĐ',
  'e': 'èéêëēĕėęěÈÉÊËĒĔĖĘĚ',
  'g': 'ĝğġģĜĞĠĢ',
  'h': 'ĥħĤĦ',
  'i': 'ìíîïĩīĭįıÌÍÎÏĨĪĬĮİ',
  'j': 'ĵĴ',
  'k': 'ķĶ',
  'l': 'ĺļľŀłĹĻĽĿŁ',
  'n': 'ñńņňÑŃŅŇ',
  'o': 'òóôõöøōŏőÒÓÔÕÖØŌŎŐ',
  'r': 'ŕŗřŔŖŘ',
  's': 'śŝşšŚŜŞŠ',
  't': 'ţťŧŢŤŦ',
  'u': 'ùúûüũūŭůűųÙÚÛÜŨŪŬŮŰŲ',
  'w': 'ŵŴ',
  'y': 'ýÿŷÝŸŶ',
  'z': 'źżžŹŻŽ',
};
