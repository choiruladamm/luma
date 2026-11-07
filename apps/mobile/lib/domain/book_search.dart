/// Logika murni Cari kata (docs/book-search.md): input user → ekspresi MATCH
/// FTS5, lokasi kata cocok di teks, dan cuplikan. Dipakai repository
/// (cuplikan) dan reader (stabilo inline).
library;

/// Minimal huruf/angka buat mulai nyari.
const bookSearchMinChars = 2;

/// Batas hasil yang ditampilin.
const bookSearchMaxHits = 500;

/// Riwayat per buku.
const bookSearchMaxRecents = 5;

/// Panjang konteks kiri-kanan kata cocok di cuplikan.
const bookSearchSnippetContext = 60;

/// Key `settings` buat riwayat cari satu buku (ikut backup).
String bookSearchRecentKey(int bookId) => 'search.recent.$bookId';

/// Satu rentang `[start, end)` di teks asli.
typedef TextRange = ({int start, int end});

/// Query yang udah divalidasi: [match] aman dipakai di `MATCH`, [ranges]
/// nyari kata yang sama di teks buat cuplikan / stabilo.
class BookSearchQuery {
  const BookSearchQuery._(this.words);

  /// Kata ter-lipat (huruf kecil, tanpa aksen), urutan sama kayak input.
  final List<String> words;

  /// Null kalau input kurang dari [bookSearchMinChars] huruf/angka.
  ///
  /// Beberapa kata = frasa (berurutan), kata terakhir prefix: `netherfield
  /// par` ketemu "Netherfield Park". Pemisah kata: apa pun selain huruf /
  /// angka, termasuk kutip lurus dan miring, jadi `don’t` = `don't` (sama
  /// kayak tokenizer unicode61 di index).
  static BookSearchQuery? parse(String input) {
    final words = _words(fold(input)).map((w) => w.text).toList();
    final letters = words.fold<int>(0, (n, w) => n + w.length);
    if (letters < bookSearchMinChars) return null;
    return BookSearchQuery._(words);
  }

  /// Ekspresi FTS5: `"netherfield par"*`. Kata dipecah di non-huruf/angka,
  /// jadi `"`, `*`, `-`, `OR`, `NEAR` dari user gak pernah jadi sintaks.
  String get match => '"${words.join(' ')}"*';

  /// Rentang tiap kemunculan frasa di [text] (kata utuh; kata terakhir
  /// boleh lanjut ke ujung kata, kayak prefix di index). Urut, gak numpuk.
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
        i += last; // gak numpuk
      }
    }
    return out;
  }
}

/// Teks pendek di sekitar kemunculan pertama + posisi kata cocok di dalamnya.
typedef BookSearchSnippet = ({String text, int matchStart, int matchEnd});

/// [bookSearchSnippetContext] huruf kiri-kanan [match], dipotong "…" di sisi
/// yang kepotong. Tanpa [match] (gak ketemu di teks): awal paragraf.
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

/// Huruf kecil + buang aksen, panjangnya sama kayak input (indeks cocok sama
/// teks asli). Cukup buat Latin; sisanya cuma di-lowercase.
String fold(String s) {
  final b = StringBuffer();
  for (final unit in s.runes) {
    final c = String.fromCharCode(unit);
    b.write(_accents[c] ?? c.toLowerCase());
  }
  final out = b.toString();
  // lowercase bisa ngubah panjang (mis. "İ"): kalau iya, jangan percaya
  // indeksnya, pakai versi tanpa lowercase buat yang berubah.
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
