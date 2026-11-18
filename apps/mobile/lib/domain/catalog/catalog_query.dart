/// User input → FTS5 MATCH expression, `"jane"* "austen"*` (prefix per word,
/// implicit AND). Trust boundary: words are split at non-letters/digits, so quotes,
/// `*`, `-`, `OR`, `NEAR` from the user never become syntax. Null = no searchable
/// word.
String? catalogMatchQuery(String input) {
  final words = input.split(_separator).where((w) => w.isNotEmpty);
  if (words.isEmpty) return null;
  return words.map((w) => '"$w"*').join(' ');
}

final _separator = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
