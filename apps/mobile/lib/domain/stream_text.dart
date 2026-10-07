import 'dart:math' as math;

/// Opasitas 4 kata terakhir teks yang lagi ditulis (board "Artinya streaming
/// · Opsi B"): makin ke ujung makin transparan, diem.
const tailAlphas = [0.8, 0.6, 0.42, 0.26];

/// Pecah [text] jadi bagian solid + kata-kata ekor (maks [tailAlphas]
/// panjangnya). Tiap kata ekor bawa spasi di belakangnya, jadi digabung
/// lagi persis sama dengan [text]. Kata ekor dipasangin ke alpha dari
/// belakang: 2 kata = 0,42 · 0,26.
({String head, List<String> tail}) splitTail(String text) {
  final words = RegExp(r'\S+').allMatches(text).toList();
  if (words.isEmpty) return (head: text, tail: const []);
  final from = math.max(0, words.length - tailAlphas.length);
  return (
    head: text.substring(0, words[from].start),
    tail: [
      for (var i = from; i < words.length; i++)
        text.substring(
          words[i].start,
          i + 1 < words.length ? words[i + 1].start : text.length,
        ),
    ],
  );
}

/// Kira-kira jumlah huruf terjemahan paragraf asli sepanjang [source].
double estimateTranslation(int source) => source * 1.05;

/// Kira-kira jumlah huruf blok makna.
const estimatedMeaning = 130.0;

/// Lebar baris placeholder (fraksi lebar kolom) buat teks sepanjang [chars]
/// huruf (board perilaku): baris = ⌈huruf × lebar huruf rata-rata ÷ lebar
/// kolom⌉, baris terakhir selebar sisanya.
List<double> placeholderRows(double chars, double charWidth, double column) {
  if (chars <= 0 || column <= 0) return const [];
  final lines = chars * charWidth / column;
  final count = lines.ceil();
  final last = (lines - (count - 1)).clamp(0.25, 1.0);
  return [for (var i = 0; i < count - 1; i++) 1.0, last];
}
