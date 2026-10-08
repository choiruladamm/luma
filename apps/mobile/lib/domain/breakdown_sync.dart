/// Blok aktif di penjelasan Bedahin (#64): yang lagi lewat garis baca.
///
/// [tops] = posisi atas tiap blok (bagian 1..n, lalu Tokoh & istilah dan
/// Praktekinnya gini kalau ada), relatif ke atas area scroll, urut. Pindah ke
/// blok berikutnya cuma kalau atasnya udah lewat [line] sejauh [margin];
/// balik ke blok sebelumnya cuma kalau atas blok aktif udah turun [margin]
/// di bawah [line]. Jadi scroll bolak-balik tipis di sekitar batas gak bikin
/// sorotan kedip. [atEnd] (mentok bawah, isinya emang ke-scroll) = blok
/// terakhir, biar blok pendek di ujung tetep bisa aktif.
int activeBlock(
  List<double> tops, {
  required double line,
  required int current,
  double margin = 24,
  bool atEnd = false,
}) {
  if (tops.isEmpty) return 0;
  if (atEnd) return tops.length - 1;
  int lastAbove(double y) {
    var i = 0;
    for (var j = 0; j < tops.length; j++) {
      if (tops[j] <= y) i = j;
    }
    return i;
  }

  final down = lastAbove(line - margin);
  if (down > current) return down;
  final up = lastAbove(line + margin);
  if (up < current) return up;
  return current.clamp(0, tops.length - 1);
}
