# Logika Pengelompokan Paragraf

## Masalah

Satu `<p>` di EPUB = satu paragraf, sependek apa pun. Di bagian dialog, banyak paragraf cuma satu baris. Tap satu baris → loading → terjemahan satu baris terasa nanggung.

## Solusi

Paragraf pendek yang berurutan **digabung jadi satu grup saat import**, disimpan di kolom `groupIndex`. Tap paragraf mana pun di grup → seluruh grup distabilo → satu request LLM → hasil di-cache per grup.

Kenapa dihitung saat import, bukan saat tap: hasilnya **stabil**, cache selalu konsisten, dan Recap bisa memakai grup sebagai unit.

## Aturan (nilai awal, tuning saat dogfooding)

| Konstanta | Nilai | Arti |
|-----------|-------|------|
| `longThreshold` | 300 karakter | Paragraf ≥ ini berdiri sendiri sebagai satu grup |
| `targetChars` | 450 karakter | Grup ditutup setelah mencapai ukuran ini |
| `maxChars` | 800 karakter | Grup tidak boleh melewati ini |
| `maxParagraphs` | 6 | Maksimal paragraf per grup |

Aturan tambahan:

- Grup **selalu diputus** di heading, pemisah adegan (`***`, `* * *`, `<hr>`), dan batas chapter.
- Heading dan pemisah adegan **tidak punya grup** (`groupIndex = null`), tidak bisa di-tap.
- `groupIndex` unik per chapter, mulai dari 0.

## Pseudocode

```dart
List<int?> assignGroups(List<Paragraph> paras) {
  final result = List<int?>.filled(paras.length, null);
  final current = <int>[]; // index paragraf di grup berjalan
  var currentChars = 0;
  var groupIndex = 0;

  void flush() {
    if (current.isEmpty) return;
    for (final i in current) result[i] = groupIndex;
    groupIndex++;
    current.clear();
    currentChars = 0;
  }

  for (var i = 0; i < paras.length; i++) {
    final p = paras[i];

    if (p.type != ParagraphType.paragraph) {
      flush(); // heading / scene break: putus grup, tanpa groupIndex
      continue;
    }

    final len = p.text.length;

    if (len >= longThreshold) {
      flush();
      current.add(i);
      flush(); // paragraf panjang = grup sendiri
      continue;
    }

    if (current.isNotEmpty &&
        (currentChars + len > maxChars || current.length >= maxParagraphs)) {
      flush();
    }

    current.add(i);
    currentChars += len;

    if (currentChars >= targetChars) flush();
  }

  flush();
  return result;
}
```

Fungsi ini **pure** (tanpa I/O), jadi wajib dibuat unit test: dialog pendek beruntun, paragraf panjang tunggal, campuran, heading di tengah, batas `maxParagraphs`.

## Perilaku UI

- Tap paragraf → semua paragraf dengan `groupIndex` yang sama distabilo.
- Bottom sheet menampilkan terjemahan **per paragraf** (jeda baris tetap terlihat seperti dialog aslinya) + satu blok "Maksud penulisnya tuh...".
- Tombol "Paragraf berikutnya" → lompat ke **grup** berikutnya.
