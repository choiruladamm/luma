/// Input user → ekspresi MATCH FTS5, `"jane"* "austen"*` (prefix per kata,
/// AND implisit). Batas kepercayaan: kata dipecah di non-huruf/angka, jadi
/// kutip, `*`, `-`, `OR`, `NEAR` dari user gak pernah jadi sintaks. Null =
/// gak ada kata yang bisa dicari.
String? catalogMatchQuery(String input) {
  final words = input.split(_separator).where((w) => w.isNotEmpty);
  if (words.isEmpty) return null;
  return words.map((w) => '"$w"*').join(' ');
}

final _separator = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
