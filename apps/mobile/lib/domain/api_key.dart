/// Bentuk API key OpenRouter: `sk-or-` + huruf/angka/`-`/`_`, tanpa spasi.
/// Cuma ngecek bentuk (gak nanya server), buat nolak teks ngawur sebelum
/// disimpen. Null = bukan bentuk key.
String? parseApiKey(String raw) {
  final key = raw.trim();
  return _shape.hasMatch(key) ? key : null;
}

final _shape = RegExp(r'^sk-or-[A-Za-z0-9_-]{8,}$');
