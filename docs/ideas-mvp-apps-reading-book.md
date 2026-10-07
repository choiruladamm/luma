# Luma: EPUB Reader + Terjemahan & Makna per Paragraf

> Nama app: **Luma**
> Desain: **Stabilo** (lihat bagian 5)
> Status: siap eksekusi MVP
> Terakhir diupdate: Oktober 2026

> **Untuk Claude Code:** file ini adalah sumber kebenaran untuk keputusan produk, data model, dan alur. Ikuti struktur di bagian 6–10. Bagian 12 ke bawah adalah rencana iterasi berikutnya dan ide kasar, **jangan dikerjakan** kecuali diminta.

---

## 1. Latar Belakang

Alur baca saat ini:

1. Download ebook EPUB
2. Buka di app Books (iPhone)
3. Select paragraf, copy
4. Pindah ke Gemini, paste, ketik pertanyaan terjemahan + makna
5. Baca jawaban, balik ke Books, cari lagi posisi terakhir

Masalah utamanya bukan kualitas terjemahan, tapi **friksi bolak-balik antar app** yang memutus fokus baca tiap beberapa menit.

## 2. Tujuan

Mengubah alur di atas menjadi **satu tap**: tap paragraf → langsung muncul terjemahan Indonesia + penjelasan makna, tanpa keluar dari halaman baca dan tanpa ngetik prompt.

### Patokan sukses MVP

- Terasa **lebih cepat dan nyaman** daripada alur Books + copy-paste ke Gemini.
- Dipakai sendiri (dogfooding) untuk baca minimal satu buku sampai selesai.

---

## 3. Fitur MVP

| # | Fitur | Keterangan |
|---|-------|-----------|
| 1 | Import EPUB | Tombol import via `file_picker`. File di-copy ke penyimpanan app, lalu **diparse sekali** ke format internal (chapter → paragraf → grup). |
| 2 | Rak buku | Grid buku dengan cover (atau cover default), judul, progres. Kartu "Lanjut baca yuk" untuk buku terakhir. Urut terakhir dibuka. |
| 3 | Halaman baca | Teks per paragraf, nyaman dibaca lama. Pengaturan Aa (font, ukuran, jarak baris, tema). |
| 4 | Daftar isi | Pindah antar chapter dari halaman baca. |
| 5 | Tap → terjemahan + makna | Tap paragraf mana pun → **seluruh grup paragrafnya** distabilo dan dikirim ke LLM. Bottom sheet: terjemahan per paragraf + satu penjelasan makna. Ada state loading, hasil, error. |
| 6 | Cache hasil AI | Disimpan di Drift per grup. Grup yang sudah pernah di-tap tidak memanggil LLM lagi. |
| 7 | Simpan posisi baca | Saat buku dibuka lagi, langsung lanjut ke posisi terakhir. |
| 8 | Pengaturan | API key OpenRouter, model ID, hapus cache. |
| 9 | Backup & restore | Export semua data (buku, terjemahan, posisi baca, pengaturan) ke satu file `.zip`, simpan ke Files/AirDrop. Restore dari file itu. Pengingat kalau sudah lama belum backup. Detail di bagian 10. |

### Di luar scope MVP (iterasi berikutnya)

- **Recap bacaan**: terjemahan + makna semua yang sudah dibaca, plus overview "sejauh ini" → **Iterasi 2, lihat bagian 12**
- Import **Luma Markdown** (hasil foto buku fisik, dikonversi di luar app) + support PDF & format lain → **ide kasar, lihat bagian 13**
- "Open in" dari app Files / share sheet iOS
- Backend proxy untuk API key (wajib kalau app dirilis ke orang lain)
- Highlight, catatan, bookmark
- Pilihan mode penjelasan (ringkas / detail / istilah sulit)
- Sinkronisasi antar device

---

## 4. Tech Stack

Mengikuti stack Mibu supaya pola dan boilerplate bisa dipakai ulang.

| Kebutuhan | Package |
|-----------|---------|
| State management | `flutter_riverpod` |
| Database lokal | `drift` |
| Routing | `go_router` |
| Parsing EPUB | parser sendiri (`archive` + `xml`), lihat catatan di bawah |
| Parsing HTML chapter | `html` (DOM parser) |
| Pilih file | `file_picker` |
| Path penyimpanan | `path_provider`, `path` |
| Hash file (anti-duplikat) | `crypto` |
| HTTP ke LLM | `dio` atau `http` |
| Simpan API key | `flutter_secure_storage` |
| Value object | `freezed` |
| Zip backup | `archive` |
| Bagikan/simpan file backup | `share_plus` |

> Cek tanggal update terakhir dan issue tiap package di pub.dev sebelum dipakai, terutama package EPUB.
>
> **Parser EPUB ditulis sendiri** (Okt 2026): `epubx` terakhir rilis Juni 2023, gagal total kalau TOC gak standar, dan nahan `archive` di 3.x. Parser sendiri cuma butuh container → OPF → spine → TOC (nav EPUB3 / NCX EPUB2) → cover, dan entri TOC yang rusak dilewatin, bukan bikin import gagal.
>
> Teks bacaan dirender dari tabel `paragraphs` (teks polos), bukan dari HTML mentah EPUB, jadi package render HTML tidak dibutuhkan untuk MVP.

---

## 5. Desain: Stabilo

Referensi lengkap (layar, komponen, token): https://claude.ai/artifact/EBwv9zJBLZQJa5WWYiaJ7F

### Prinsip

1. **Teks dulu, UI belakangan.** Halaman baca bersih. UI muncul hanya saat dibutuhkan (sheet artinya, Aa, progres tipis di bawah).
2. **Kuning = yang lagi penting.** Stabilo hanya untuk aksi utama dan paragraf/grup yang sedang di-tap. Satu layar, satu tombol kuning.
3. **Malem tetep adem.** Mode gelap pakai hitam hangat, bukan hitam pekat.

### Font

| Font | Dipakai untuk |
|------|---------------|
| Bricolage Grotesque | UI, judul, label, tombol |
| Atkinson Hyperlegible | Teks bacaan + isi sheet (default, opsi "Jelas") |
| Literata | Opsi bacaan "Kayak buku" |
| Font sistem iOS | Opsi bacaan "Bawaan iOS" |

Bundle font sebagai asset (jangan fetch runtime).

### Token warna utama

| Token | Terang | Gelap |
|-------|--------|-------|
| canvas | `#FFFBEF` | `#22201C` |
| sheet | `#FFFDF6` | `#2C2A25` |
| muted | `#F2EDDD` | `#36332D` |
| ink | `#1C1C1C` | `#DDD7C8` |
| ink2 | `#5E5A4E` | `#A19B8E` |
| accent (stabilo) | `#FFD84D` | `#E9C75A` |
| pink | `#FFC2D3` | `#D99BAE` |

Implementasi Flutter: `ThemeExtension` (`StabiloColors`) dengan satu set terang dan satu set gelap. Detail token lain (track, outline, scrim, highlight) ada di artifact.

### Halaman baca imersif (ReaderCapsule)

Pas baca, layar isinya cuma teks + garis progres tipis. Menu nongol sebagai dua kapsul ngambang kalau dibutuhin. Top bar 60pt cuma buat Rak & Pengaturan. Spek lengkap di board "Baca imersif · ReaderCapsule" (+ layar 03 Baca, 03b imersif, 03c Lanjut baca).

- **Kapsul atas**: tinggi 58, radius penuh, 6pt di bawah safe area atas, kiri-kanan 24. Isi: balik · judul + "Bab N · judul bab" · daftar isi · Aa. Tombol 44 bulet muted; tombol yang sheet-nya lagi kebuka (Daftar isi / Aa) jadi kuning.
- **Kapsul bawah**: tinggi 40, 14pt di atas safe area bawah, di tengah. Persen + bar 88 + "±N mnt lagi" (atau "Bab N beres"). Cuma info.
- **Gaya kapsul**: latar sheet. Terang: garis 1,5 ink + bayangan tekan 2 + bayangan lembut. Gelap: garis `#46423A` + bayangan lembut.
- Teks yang lewat di belakang kapsul dimudarin pake **EdgeFade** (lihat di bawah), bukan gradien warna latar.
- **Garis progres** 2pt selebar layar, tepat di atas safe area bawah (gak kepotong sudut layar, gak numpuk home indicator). Terang `#E6B800`, gelap `#E9C75A`, track ink 8–10%. Progres per buku; 100% di layar akhir buku.
- Kapsul itu **overlay**: teks gak loncat pas kapsul muncul/ngumpet. Teks awal bab mulai 86pt di bawah safe area atas (board: 140) biar judul bab gak ketutup.

### EdgeFade (tepi area scroll)

Board "EdgeFade · tepi area scroll". Tepi area scroll mudar halus pake **mask** (`ShaderMask` + `BlendMode.dstIn`, widget `EdgeFadeScroll`): isinya yang transparan, bukan gradien warna latar, jadi aman di terang & gelap. Fade atas cuma muncul kalau udah di-scroll, fade bawah cuma kalau masih ada isi di bawah, isi muat = gak ada fade. Muncul/ilang 150 ms. Gak dipasang di elemen yang gak ikut ke-scroll (judul, tombol aksi, kapsul).

| Tempat | Fade atas | Fade bawah | Catatan |
|--------|-----------|------------|---------|
| Sheet (Aa, Daftar isi, Artinya, `SheetFrame`, Ringkasan pulihin) | 20pt | 20pt | Standar |
| Layar penuh (Rak, Pengaturan) | 20pt di bawah header yang nempel | 34pt (= safe area) | Rak: header + "Semua buku" nempel, tanpa garis pemisah. Pengaturan: balik + judul nempel |
| Baca · kapsul keliatan | 48pt dari tepi kapsul | 48pt ke tepi kapsul | Teks di belakang kapsul ±18%. Status bar & di bawah garis progres kosong. Awal bab gak ada fade atas |
| Baca · imersif | – | 24pt, selesai pas di garis progres | Di bawah garis progres kosong |

Varian kapsul ↔ imersif di-interpolasi sepanjang animasi kapsul ngumpet/muncul, gak loncat. Menu tekan lama & urutkan cuma 2–3 item, gak pernah scroll, jadi belum dipasang.

### Pengaturan Aa

Sheet "Atur bacaan lo" (board 07), dibuka dari tombol Aa di kapsul. Tiap pilihan langsung disimpen dan langsung keliatan di teks; scrim-nya tipis (8% terang, 18% gelap) biar teks di belakang jadi preview. Posisi baca nempel: titik yang lagi di garis atas tetep di situ pas ukuran/font/jarak/margin diganti.

- Ukuran huruf: 7 step 16 · 17 · 18 · **18,5** · 20 · 22 · 24 (tombol A kecil / A gede)
- Font: **Jelas** (Atkinson Hyperlegible) / Kayak buku (Literata, jarak baris +0,05) / Bawaan iOS (SF)
- Jarak baris: Rapat 1,5 / **Pas 1,65** / Lega 1,85; mode gelap +0,05
- Margin teks: Sempit 16 / **Pas 24** / Lega 32. Area tap margin minimal 24pt: di Sempit, 8pt pinggir kolom ikut diitung area kosong
- Tema: Terang / Gelap / **Ikut iOS** → `themeMode` app
- Tampilan layar: "Sembunyiin jam & baterai" (**nyala**) dan "Tampilin garis progres" (**nyala**), pake Switch dari board Komponen dasar (51 × 31)
- Disimpen per perangkat (bukan per buku) di tabel `settings`, ikut backup. Nilai yang gak dikenal (backup rusak) balik ke default

### Copy

Bahasa Indonesia gaya Gen Z, santai. Contoh: "Rak buku lo", "Lanjut baca yuk", "Artinya gini nih", "Maksud penulisnya tuh...", "Bentar, lagi mikir...", "Yah, gagal nih".

### Layar yang sudah didesain

Semua layar MVP awal sudah final (terang + gelap): rak kosong/berisi, baca, artinya (loading / hasil / error / udah disalin / API key kosong) dengan highlight grup, Aa, daftar isi, akhir bab, akhir buku, import (proses / berhasil / duplikat / rusak / bukan EPUB / DRM), urutkan rak, tekan lama buku, info buku, konfirmasi hapus, pengaturan, penanda grup yang sudah diterjemahkan.

### Layar yang masih didesain

Backup & restore (bagian 10): bagian Backup di Pengaturan, proses export, restore (pilih file → ringkasan → konfirmasi → proses → berhasil / gagal), banner pengingat backup.

---

## 6. Data Model (Drift)

Prinsip: **file diparse sekali saat import** ke format internal. Reader, AI, dan Recap hanya membaca tabel di bawah, tidak pernah parse file ulang.

> **Keputusan penting: ID chapter stabil.** Chapter bisa masuk tidak berurutan (mis. import Markdown chapter 3, lalu 7, lalu 5; lihat bagian 13). Karena itu semua tabel lain menunjuk ke `chapters.id` (stabil), **bukan** ke posisi/urutan chapter. Urutan tampil diatur kolom `sortOrder`.

### `books`

| Kolom | Tipe | Catatan |
|-------|------|---------|
| id | int (PK) | |
| sourceType | text | `epub` (MVP) / `markdown` (nanti) |
| bookKey | text? (unique) | Slug untuk mencocokkan import Markdown ke buku yang sama (mis. `atomic-habits`). Null untuk EPUB |
| title | text | |
| author | text? | |
| fileName | text? | **Nama file saja**, bukan absolute path. Null untuk buku Markdown |
| coverName | text? | Nama file cover. Null → pakai cover default |
| hash | text? (unique) | SHA-256 isi file EPUB, untuk cegah import dobel |
| parserVersion | int | Versi logika parsing + grouping. Naik → re-import & invalidasi cache buku itu |
| totalChars | int | Untuk hitung persentase baca (hanya bermakna untuk buku lengkap) |
| createdAt | datetime | |
| lastOpenedAt | datetime? | Untuk urutan rak |
| firstOpenedAt | datetime? | Pertama kali dibuka. Diisi sekali, gak berubah lagi |
| readingSeconds | int (default 0) | Total waktu baca aktif, ditampilkan di layar akhir buku ("6 jam 20 mnt", atau "45 mnt" di bawah 1 jam) |

**Waktu baca aktif** dihitung selama halaman baca kebuka dan app di foreground. Berhenti kalau 2 menit gak ada scroll/tap (2 menit itu ikut dihitung), lanjut lagi pas ada interaksi. Disimpan bertahap (tiap scroll berhenti, pindah bab, app ke background, keluar halaman baca), jadi app yang dimatiin iOS cuma kehilangan beberapa detik terakhir.

### `chapters`

| Kolom | Tipe | Catatan |
|-------|------|---------|
| id | int (PK, autoincrement) | **Kunci stabil**, dipakai tabel lain |
| bookId | int (FK) | |
| sortOrder | int | Urutan tampil. EPUB: urutan TOC. Markdown: dari nomor chapter |
| chapterNumber | int? | Nomor bab asli dari buku (untuk Markdown / daftar isi) |
| title | text | Dari TOC/nav EPUB, fallback "Bab N" |
| charOffset | int | Jumlah karakter sebelum chapter ini (untuk persentase). Dihitung ulang kalau ada chapter disisipkan |

Index: `(bookId, sortOrder)`.

### `paragraphs`

| Kolom | Tipe | Catatan |
|-------|------|---------|
| chapterId | int (FK → chapters.id) | |
| paragraphIndex | int | Urutan dalam chapter |
| groupIndex | int? | Grup untuk tap/AI. Null untuk heading & pemisah adegan (tidak bisa di-tap) |
| type | text | `paragraph` / `heading` / `scene_break` |
| text | text | Teks polos yang sudah dinormalisasi |

Unique key: `(chapterId, paragraphIndex)`. Index tambahan: `(chapterId, groupIndex)`.

### `reading_progress`

| Kolom | Tipe | Catatan |
|-------|------|---------|
| bookId | int (PK) | |
| chapterId | int (FK) | |
| paragraphIndex | int | Paragraf paling atas yang keliatan di bawah safe area atas |
| paragraphOffset | real (default 0.0) | Bagian paragraf itu yang udah lewat garis atas, **fraksi tinggi paragraf** 0.0–1.0 (bukan piksel, biar tetep pas kalau font/ukuran/jarak baris diganti di Aa). Di-clamp 0–1 pas nyimpen dan pas baca |
| updatedAt | datetime | |

### `ai_results`

| Kolom | Tipe | Catatan |
|-------|------|---------|
| chapterId | int (FK) | |
| groupIndex | int | |
| translations | text | JSON array string, satu item per paragraf di grup (urut) |
| meaning | text | Satu penjelasan untuk seluruh grup |
| model | text | Model yang dipakai |
| createdAt | datetime | |

Unique key: `(chapterId, groupIndex)`.

> ⚠️ **Indeks paragraf dan grup harus stabil.** Logika parsing dan grouping jangan diubah sembarangan setelah ada data. Kalau harus berubah, naikkan `parserVersion`, re-import buku, dan hapus `ai_results` buku tersebut.

### Versi schema & migrasi

| Versi | Perubahan |
|-------|-----------|
| 1 | Awal |
| 2 | `books.firstOpenedAt`, `books.readingSeconds` |
| 3 | `reading_progress.paragraphOffset` |

Tiap ubah tabel: naikkan `schemaVersion`, tambah langkah di `onUpgrade`, dan test migrasi dari versi sebelumnya (data tetap utuh, schema hasil migrasi sama dengan install baru). Restore backup dari schema lama ikut dimigrasi saat database dibuka (bagian 10).

### Pengaturan

API key di `flutter_secure_storage`. Model ID, preferensi Aa, dan `lastBackupAt` di tabel `settings` sederhana (key-value) di Drift, supaya ikut ter-backup. Model LLM: `ai.model` (model ID OpenRouter, default `z-ai/glm-5.3-flash`; pilihan dari daftar kandidat di bagian 9). API key di Keychain dengan kunci `openrouter_api_key`, disimpen tiap diketik (kosong = dihapus). "Hapus cache" di Pengaturan = kosongin `ai_results` setelah konfirmasi; Pengaturan nampilin jumlah paragraf yang udah diterjemahin + ukuran teksnya. Kunci Aa: `reader.size` (indeks step 0–6), `reader.font`, `reader.spacing`, `reader.margin`, `theme` (nama enum), `reader.hideStatusBar`, `reader.showProgressLine` (`true`/`false`). Hindari `shared_preferences` untuk data yang perlu ikut backup.

---

## 7. Logika Pengelompokan Paragraf

### Masalah

Satu `<p>` di EPUB = satu paragraf, sependek apa pun. Di bagian dialog, banyak paragraf cuma satu baris. Tap satu baris → loading → terjemahan satu baris terasa nanggung.

### Solusi

Paragraf pendek yang berurutan **digabung jadi satu grup saat import**, disimpan di kolom `groupIndex`. Tap paragraf mana pun di grup → seluruh grup distabilo → satu request LLM → hasil di-cache per grup.

Kenapa dihitung saat import, bukan saat tap: hasilnya **stabil**, cache selalu konsisten, dan Recap bisa memakai grup sebagai unit.

### Aturan (nilai awal, tuning saat dogfooding)

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

### Pseudocode

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

### Perilaku UI

- Tap paragraf → semua paragraf dengan `groupIndex` yang sama distabilo.
- Bottom sheet menampilkan terjemahan **per paragraf** (jeda baris tetap terlihat seperti dialog aslinya) + satu blok "Maksud penulisnya tuh...".
- Tombol "Paragraf berikutnya" → lompat ke **grup** berikutnya.

---

## 8. Arsitektur & Alur

### Routing (go_router)

- `/` → Rak buku
- `/reader/:bookId` → Halaman baca (posisi dari `reading_progress`)
- `/settings` → Pengaturan (termasuk bagian Backup & restore)
- Bottom sheet artinya, Aa, dan Daftar isi **bukan route**, cukup `showModalBottomSheet`.

### Provider utama (Riverpod)

- `booksStreamProvider` → `StreamProvider` dari query Drift, untuk grid rak.
- `chapterParagraphsProvider(chapterId)` → paragraf satu chapter dari Drift.
- `bookChaptersProvider(bookId)` → daftar chapter terurut `sortOrder` (untuk Daftar isi).
- `groupAiProvider(GroupRef)` → `FutureProvider.autoDispose.family`:
  1. Cek `ai_results`
  2. Kalau belum ada: ambil paragraf grup + sampe 3 paragraf (bukan heading/pemisah) sebelum paragraf pertama grup di chapter yang sama sebagai konteks
  3. Panggil LLM (API key dibaca dari Keychain, model dari `ai.model`)
  4. Validasi jumlah `translations` = jumlah paragraf grup
  5. Simpan ke Drift, return hasil

  **Auto-retry Riverpod 3 dimatiin** (`retry: (_, _) => null`): tiap percobaan motong saldo. Gagal → `AsyncError` berisi `AiException`, dicoba ulang cuma lewat `ref.invalidate` (tombol "Coba lagi"). Hasil tetep disimpen walaupun sheet keburu ditutup. Dua tap ke grup yang sama pas lagi loading = satu request.
- `importControllerProvider` → `Notifier` untuk state import (idle / processing / success / error / duplicate).

`GroupRef` = record `({int chapterId, int groupIndex})`: `==`/`hashCode` per nilai udah bawaan Dart, gak perlu `freezed`.

### Alur import

1. Pilih file EPUB via `file_picker`
2. Baca bytes, hitung SHA-256 → kalau hash sudah ada → state **duplikat**
3. Parse EPUB di isolate (parser sendiri): judul, penulis, cover, chapter dari TOC/nav (bukan dari jumlah file HTML), `sortOrder` = urutan TOC. **Parse dulu sebelum nyalin file**, jadi EPUB jelek gak ninggalin apa-apa
4. Per chapter: parse HTML (package `html`), ambil blok teks (`p`, `div` berisi teks, heading, `hr`), normalisasi whitespace, buang paragraf kosong, lewati bagian non-isi (lihat bagian 14)
5. Jalankan `assignGroups` per chapter
6. Copy ke `Documents/books/{hash}.epub`, cover ke `Documents/covers/{hash}.{ext}`
7. Insert `books` + `chapters` + `paragraphs` dalam **satu transaksi** Drift
8. Gagal setelah nyalin → hapus file yang sudah di-copy (transaksi di-rollback), state **error**

Parsing buku besar bisa berat: jalankan di isolate (`compute` / `Isolate.run`) supaya UI tidak freeze.

### Posisi baca

- **Titik acuan** = paragraf paling atas yang keliatan di bawah safe area atas + `paragraphOffset` (bagian paragraf itu yang udah lewat garis tersebut, fraksi 0–1).
- **Nyimpen**: cuma setelah scroll dari jari (lompatan restore gak dihitung), debounce ±500 ms setelah scroll berhenti. Langsung disimpen pas app ke background (`AppLifecycleState` selain `resumed`), pindah bab, dan keluar halaman baca. Gak pernah nulis ke DB tiap frame.
- **Restore** (buka buku): lompat ke paragraf tersimpan, terus geser sesuai offset supaya titiknya ada di ±⅓ tinggi layar (ada konteks di atasnya). Tinggi paragraf baru ketahuan setelah layout, jadi dihitung di post-frame callback; isi bab disembunyiin sampe udah di posisi, terus fade in. Kepotong di ujung scroll kalau titiknya deket akhir chapter.
- Satu chapter dirender utuh (bukan list lazy), jadi posisi semua paragraf ketahuan tanpa package tambahan.

### Perilaku kapsul baca

- Scroll turun ≥ 24pt → dua kapsul geser keluar (200 ms, ease-out). Naik ≥ 12pt atau flick ke atas → muncul. Selama jari masih nge-drag, kapsul ngikutin 1:1, terus snap pas dilepas. Ambang dihitung per arah (ganti arah = mulai dari 0).
- Awal bab (80pt pertama) dan akhir bab (paragraf terakhir keliatan) → kapsul muncul sendiri. Pindah bab → muncul.
- Cuma scroll dari jari yang dihitung; lompatan restore posisi gak ngumpetin kapsul.
- **Zona tap**: paragraf → sheet Artinya (kotak paragraf selebar kolom teks, termasuk sisa kosong di baris pendek). Area kosong (margin kiri-kanan, sela antar paragraf, di bawah teks terakhir, heading/pemisah adegan) → munculin/ngumpetin kapsul. Tengah layar gak punya fungsi khusus. Tap kosong pas sheet kebuka → nutup sheet (barrier sheet).
- **Sheet dari kapsul (Daftar isi, Aa)**: kapsul atas tetep keliatan di atas scrim, tombol yang sheet-nya kebuka jadi kuning, tap tombol itu lagi = nutup sheet. Sheet mulai 12pt di bawah kapsul. Implementasinya: barrier sheet transparan, scrim digambar halaman baca di bawah kapsul; tap di area kapsul kena barrier → sheet ketutup.
- **Sheet Artinya** (dibuka dari teks, #23): kapsul ngumpet; sheet naik barengan halaman di-scroll sampe bawah grup = atas sheet − 16pt (grup kepanjangan: atas grup = safe area + 16pt, sheet di detent medium). "Lanjut" nge-scroll grup berikutnya ke atas sheet; pas ditutup halaman diem di grup terakhir. Cuma buka satu grup → halaman balik ke posisi sebelum sheet dibuka.
- **Akhir bab**: kartu akhir bab keliatan → dua kapsul muncul, kapsul bawah nulis "Bab N beres". **Akhir buku**: layar sendiri tanpa kapsul, garis progres penuh 100%, cover pake cover default (tanpa bulatan huruf), status bar balik.
- **Lanjut baca** (buka buku yang ada posisi tersimpannya): kapsul muncul 2,5 detik buat orientasi terus ngumpet sendiri (batal kalau user udah scroll duluan). Grup tempat posisi tersimpan dikasih kilatan stabilo sekali, 0 → 60% → 0 dalam 1,2 detik. "Kurangi gerakan" iOS nyala → tanpa kilatan, gantinya garis kiri 4pt yang ilang setelah 3 detik.
- Status bar iOS ngumpet bareng kapsul kalau toggle "Sembunyiin jam & baterai" nyala (default nyala; togglenya di Aa, #18). Keluar halaman baca → status bar balik.

### Persentase baca

`(chapters.charOffset + jumlah karakter paragraf sebelum posisi) / books.totalChars`.

Buku Markdown yang chapternya belum lengkap (nanti, bagian 13) tidak punya total yang pasti, jadi tampilkan progres per chapter saja.

### Gotcha iOS

- **Jangan simpan absolute path di database.** Path container app iOS bisa berubah setiap update/reinstall. Simpan nama file, gabungkan dengan `getApplicationDocumentsDirectory()` saat runtime.
- File dari picker biasanya ada di folder sementara, jadi wajib di-copy ke Documents.
- Buat folder `books/` dan `covers/` saat app start (`create(recursive: true)`).

---

## 9. Integrasi LLM

### Provider

OpenRouter (API OpenAI-compatible, base URL `https://openrouter.ai/api/v1`).

### Kandidat model (harga per 1 juta token, cek ulang di OpenRouter)

| Model | Model ID | Input | Output | Catatan |
|-------|----------|-------|--------|---------|
| GLM 5.3 Flash | `z-ai/glm-5.3-flash` | $0.075 | $0.25 | Termurah, banyak provider. **Default awal.** |
| DeepSeek V4.1 Flash | `deepseek/deepseek-v4.1-flash` | $0.15–0.30 | $0.60–1.20 | Harga beda jam sibuk / tidak sibuk |
| Qwen 3.8 Flash | `qwen/qwen3.8-flash` | $0.15 | $0.47 | Keluarga Qwen kuat di multibahasa |

Estimasi: ~800 token input + ~400 token output per tap → dengan GLM 5.3 Flash sekitar **$0.16 per 1.000 tap**.

### Aturan implementasi

- **Model ID bisa diganti dari Pengaturan**, jangan di-hardcode.
- **Matikan reasoning** lewat parameter `reasoning` di request (token reasoning dihitung sebagai output dan bikin lambat).
- Minta output **JSON**; strip code fence sebelum `jsonDecode`.
- **Validasi** `translations.length` = jumlah paragraf grup. Kalau tidak cocok, retry sekali; kalau masih gagal, tampilkan state error.
- Timeout request ±30 detik → state error ("Yah, gagal nih").
- API key belum diisi → jangan panggil API, tampilkan state "API key belum diisi" dengan tombol ke Pengaturan.
- Untuk MVP pribadi, API key disimpan lokal di `flutter_secure_storage`. Kalau mau rilis, wajib lewat backend proxy.
- Atur preferensi provider di OpenRouter kalau ingin menghindari provider yang memakai data untuk training.

**Implementasi** (`OpenRouterService`):

- `POST /chat/completions` dengan `reasoning: {"enabled": false}` dan `response_format: {"type": "json_object"}`. Timeout connect/send/receive 30 detik.
- Sebagian model gak bisa reasoning-nya dimatiin (GLM 5.3 Flash: 400 "Reasoning is mandatory..."). Kena error itu → kirim ulang sekali dengan `reasoning: {"effort": "minimal", "exclude": true}`.
- Jawaban: ambil objek JSON dari `{` pertama sampe `}` terakhir (buang code fence / basa-basi), cek `translations` = list string sejumlah paragraf TARGET dan `meaning` gak kosong. Gak valid → coba ulang sekali, masih gagal → `invalidResponse`.
- Error bertipe (`AiError`): `noApiKey` (API gak dipanggil), `timeout`, `network`, `http` (bawa status: 401 key ditolak, 402 saldo abis), `invalidResponse`. Error HTTP gak di-retry.
- API key dibaca langsung dari Keychain tiap request (bukan di-cache), model dari `ai.model`.
- Cek key di Pengaturan: `GET /key` (debounce 600 ms abis ngetik). 2xx → "Key-nya jalan", 401/403 → "Key-nya ditolak OpenRouter", offline/gagal → cuma keterangan Keychain.
- Coba ke OpenRouter beneran: `make live` (key dari `.env` di root repo, `OPENROUTER_API_KEY=...`, di-gitignore), model lain `make live m=<model id>`. Tanpa key, test itu di-skip. Ketiga kandidat lulus (Okt 2026).

### Draft prompt

**System:**

```
Kamu adalah asisten membaca. Pengguna sedang membaca buku berbahasa Inggris
dan ingin memahami bagian TARGET, yang terdiri dari satu atau beberapa
paragraf bernomor.

Tugas:
1. Terjemahkan SETIAP paragraf TARGET ke Bahasa Indonesia yang natural,
   bukan kata per kata. Satu paragraf = satu item terjemahan. Jumlah dan
   urutan item harus sama dengan paragraf TARGET.
2. Jelaskan makna TARGET secara keseluruhan dalam 2–4 kalimat Bahasa
   Indonesia yang santai, kayak jelasin ke temen: apa maksud penulis,
   kaitannya dengan konteks sebelumnya, dan istilah sulit kalau ada.

KONTEKS hanya untuk membantu pemahaman, jangan diterjemahkan.

Balas HANYA dengan JSON, tanpa teks lain:
{"translations": ["...", "..."], "meaning": "..."}
```

**User:**

```
KONTEKS (paragraf sebelumnya):
{paragraf_konteks}

TARGET:
[1] {paragraf_1}
[2] {paragraf_2}
...
```

> Sesuaikan prompt dengan cara bertanya ke Gemini yang selama ini sudah terbukti cocok.

### Evaluasi model

Ambil 10–20 grup dari buku yang sedang dibaca (campur dialog pendek dan paragraf panjang), jalankan ke ketiga model dengan prompt yang sama, bandingkan kualitas terjemahan dan penjelasan secara langsung.

---

## 10. Backup & Restore

### Kenapa masuk MVP

Luma diinstall tanpa Apple Developer Program berbayar, jadi build harus diinstall ulang dari Xcode **setiap 7 hari**.

- Install ulang **di atas app yang sudah ada** (bundle ID & tim signing sama) biasanya **mempertahankan data**.
- Data **hilang** kalau app dihapus (mis. saat membereskan masalah signing), bundle ID berubah, atau ganti HP.

Terjemahan di `ai_results` dibayar pakai saldo OpenRouter dan progres baca tidak bisa dibuat ulang, jadi wajib ada backup manual yang gampang.

### Prinsip

- **Satu file berisi semuanya**, disimpan **di luar app** (Files / iCloud Drive / AirDrop ke Mac). Backup yang disimpan di dalam folder app ikut hilang kalau app dihapus.
- **Restore = ganti semua data** (bukan merge). Merge ditunda.
- **Aman**: restore diekstrak ke folder sementara dulu, data lama baru diganti kalau semua langkah berhasil.
- **API key tidak ikut** di-backup (alasan keamanan). Setelah restore, kalau API key kosong, app minta diisi ulang.

### Isi file backup

Nama: `luma-backup-YYYYMMDD-HHmm.zip` (pakai ekstensi `.zip` biasa supaya tidak perlu daftar tipe file custom di iOS).

```
luma-backup-20261006-2130.zip
├── manifest.json
├── luma.sqlite        ← snapshot database Drift
├── books/             ← file EPUB asli ({hash}.epub)
└── covers/            ← gambar cover ({hash}.png)
```

`manifest.json`:

```json
{
  "format": "luma-backup",
  "formatVersion": 1,
  "appVersion": "0.1.0",
  "schemaVersion": 1,
  "createdAt": "2026-10-06T21:30:00+07:00",
  "counts": { "books": 7, "aiResults": 1240 }
}
```

### Alur export (backup)

1. Pengaturan → "Backup sekarang"
2. Buat snapshot database yang konsisten dengan `VACUUM INTO '<tmp>/luma.sqlite'` (aman walau database sedang dipakai / mode WAL)
3. Tulis `manifest.json`
4. Zip snapshot + folder `books/` + `covers/` (pakai package `archive`, jalankan di isolate karena file EPUB bisa besar)
5. Buka share sheet (`share_plus`) → user pilih "Save to Files", iCloud Drive, atau AirDrop
6. Simpan `lastBackupAt` di tabel `settings`, hapus file zip sementara

### Alur import (restore)

1. Pengaturan → "Pulihin dari backup" → pilih file `.zip` via `file_picker`
2. Ekstrak ke folder sementara
3. Validasi:
   - `manifest.json` ada dan `format` = `luma-backup`
   - `schemaVersion` backup **≤** schema app sekarang (backup dari versi lebih baru → tolak)
   - `luma.sqlite` bisa dibuka
4. Tampilkan ringkasan: jumlah buku, jumlah terjemahan, tanggal backup
5. Konfirmasi: "Semua data di Luma sekarang bakal diganti. Lanjut?"
6. Tutup koneksi Drift → ganti file database + folder `books/` & `covers/` → buka lagi database (migrasi Drift otomatis jalan kalau backup dari schema lama)
7. Invalidate provider Riverpod (atau restart ke Rak)
8. Gagal di langkah mana pun → hapus folder sementara, data lama tetap utuh

### Pengingat backup

- Pengaturan menampilkan "Backup terakhir: 3 hari lalu" (atau "Belum pernah backup").
- Kalau `lastBackupAt` lebih dari **6 hari** (sebelum siklus install ulang 7 hari), tampilkan banner kecil di Rak: "Udah 6 hari belum backup nih" dengan tombol "Backup".
- Banner bisa ditutup, muncul lagi besoknya.

### Catatan

- Jangan bandingkan absolute path dari backup. Semua path di database sudah berupa nama file (bagian 6), jadi tetap valid setelah restore.
- Ukuran backup kira-kira = total ukuran EPUB + sedikit untuk database. Tampilkan ukuran setelah backup selesai.
- Unit test: round-trip export → restore ke database kosong menghasilkan data yang sama.

### Ditunda (setelah MVP)

- Export/import **per buku** (satu buku + terjemahannya, untuk dipindah atau dibagikan)
- Restore **merge** (gabung dengan data yang ada)
- Export terjemahan + makna ke Markdown (nyambung dengan Recap)

---

## 11. Urutan Pengerjaan

1. Setup project: struktur dari Mibu, Drift, go_router, theme Stabilo (`ThemeExtension` + font asset)
2. Schema Drift: `books`, `chapters`, `paragraphs`, `reading_progress`, `ai_results`, `settings` (pakai `chapters.id` sebagai kunci, lihat bagian 6)
3. `assignGroups` + unit test
4. Import EPUB: copy file, metadata, cover, parse chapter → paragraf → grup (isolate + transaksi), state import
5. Rak buku: kosong + berisi + kartu "Lanjut baca yuk" + cover default
6. Halaman baca + Daftar isi + Aa
7. Tap grup → highlight + bottom sheet (loading / hasil / error) + OpenRouter
8. Cache `ai_results`
9. Simpan & restore posisi baca + persentase
10. Pengaturan: API key, model ID, hapus cache
11. Backup & restore (bagian 10) + pengingat backup
12. Dogfooding, catat pain point di bagian 14

---

## 12. Iterasi 2: Recap Bacaan

### Tujuan

Misal sudah baca 18% buku. Pengguna bisa membuka layar Recap untuk:

1. Melihat **terjemahan + makna semua paragraf** dari awal sampai posisi baca sekarang, dikelompokkan per chapter.
2. Membaca **overview "sejauh ini"**: ringkasan keseluruhan bagian yang sudah dibaca.

Berguna untuk baca sekilas ulang tanpa harus tap paragraf satu per satu.

### Prinsip

- **Bebas spoiler**: tidak pernah memproses teks setelah posisi baca terakhir.
- **Reuse cache**: hasil disimpan ke `ai_results` yang sama dengan fitur tap, **per grup**. Grup yang diproses lewat Recap langsung instan saat di-tap di reader, dan sebaliknya.
- **Unit = grup** (bagian 7), bukan paragraf tunggal.
- **Per chapter, bukan per halaman**: EPUB bersifat reflowable, jumlah "halaman" berubah tergantung ukuran font dan layar. Chapter adalah unit yang stabil.
- **Persentase** dihitung dari posisi paragraf (atau jumlah karakter) terhadap total buku.

### Bagian A: Terjemahan + makna semua yang sudah dibaca

Alur:

1. Buka layar Recap
2. Cari grup dari awal buku sampai posisi baca yang **belum** ada di `ai_results`
3. Proses yang belum ada dalam **chunk beberapa grup per request** (mis. 3–5 grup, ±1.500–2.500 karakter)
4. Simpan hasil per grup ke `ai_results`
5. Tampilkan bertahap sambil job berjalan

Format balasan LLM per chunk:

```json
[
  {"group": 12, "translations": ["...", "..."], "meaning": "..."},
  {"group": 13, "translations": ["..."], "meaning": "..."}
]
```

Validasi: pastikan setiap `group` yang dikirim ada di balasan dan jumlah `translations` cocok dengan jumlah paragrafnya. Grup yang hilang atau gagal di-parse masuk antrean retry.

Draft prompt chunk (system):

```
Kamu adalah asisten membaca. Teks dibagi menjadi beberapa GRUP bertanda
[grup N], tiap grup berisi satu atau beberapa paragraf. Untuk SETIAP grup:
terjemahkan tiap paragrafnya ke Bahasa Indonesia yang natural (satu item
per paragraf, urutan sama), lalu beri satu penjelasan makna singkat
(1–3 kalimat, santai). Gunakan KONTEKS hanya untuk pemahaman.

Balas HANYA dengan JSON array, satu objek per grup:
[{"group": <int>, "translations": ["..."], "meaning": "..."}]
```

### Bagian B: Overview "sejauh ini"

Pakai **ringkasan bertingkat**, jangan kirim seluruh teks yang sudah dibaca setiap kali:

1. **Chapter selesai dibaca** → buat ringkasan chapter sekali, simpan.
2. **Chapter yang sedang dibaca** → buat ringkasan sampai paragraf terakhir yang dibaca. Update kalau posisi baca sudah maju cukup jauh.
3. **Overview keseluruhan** → dibuat dari gabungan ringkasan chapter, bukan dari teks mentah.

Hasilnya lebih murah, lebih cepat, dan otomatis bebas spoiler.

### Tambahan data model

**`chapter_summaries`**

| Kolom | Tipe | Catatan |
|-------|------|---------|
| chapterId | int (FK) | |
| summary | text | Bahasa Indonesia |
| coveredUntilParagraph | int | Sampai paragraf mana ringkasan ini dibuat |
| model | text | |
| updatedAt | datetime | |

Unique key: `(chapterId)`.

**`book_overviews`**

| Kolom | Tipe | Catatan |
|-------|------|---------|
| bookId | int (PK) | Satu overview aktif per buku |
| overview | text | |
| coveredUntilChapterId | int | |
| coveredUntilParagraph | int | |
| progressPercent | real | Persentase saat overview dibuat |
| updatedAt | datetime | |

Overview dibuat ulang kalau posisi baca sudah maju melewati ambang tertentu (misal +5% atau ganti chapter).

### Layar Recap

- **Atas**: kartu overview "Sejauh ini (18%)"
- **Bawah**: daftar chapter (expand/collapse), masing-masing dengan ringkasan chapter
- **Saat chapter dibuka**: paragraf dengan terjemahan + makna
- **Toggle tampilan**: terjemahan saja / makna saja / berdampingan dengan teks asli
- **Tap paragraf** → lompat ke posisi tersebut di reader
- **Progress bar** saat job berjalan, misal "45 / 120 bagian"

### Catatan implementasi

- Job pengisian dibuat sebagai Riverpod `Notifier` yang menyimpan state progres (total grup, selesai, gagal).
- Batasi **3–5 request paralel**, pakai retry dengan backoff, dan sediakan tombol batal.
- iOS akan menghentikan proses saat app ditutup atau masuk background. Karena hasil disimpan per paragraf, job cukup **melanjutkan yang belum selesai** saat app dibuka lagi.
- Pakai endpoint OpenRouter **standar**, bukan varian `:batch`. Untuk GLM 5.3 Flash, varian batch justru lebih mahal (per Oktober 2026).
- Opsional: **prefetch** beberapa paragraf ke depan di background saat membaca, supaya tap terasa instan dan Recap makin lengkap.

### Estimasi biaya

Buku rata-rata sekitar 100 ribuan token teks. Dengan GLM 5.3 Flash, terjemahan + makna **satu buku penuh** kira-kira **~$0.10**. Recap 18% hanya beberapa sen. Tantangan utama ada di UX dan kecepatan, bukan biaya.

### Urutan pengerjaan Iterasi 2

1. Job pengisian grup yang belum diterjemahkan (chunk + progress + retry)
2. Layar Recap: daftar chapter + paragraf + toggle tampilan
3. Ringkasan per chapter (`chapter_summaries`)
4. Overview keseluruhan (`book_overviews`)
5. Lompat dari Recap ke posisi di reader

---

## 13. Ide Kasar: Import Luma Markdown, Foto Buku Fisik & Format Lain

> Status: ide kasar, belum final. Kandidat **Iterasi 3**. Yang sudah diambil ke MVP hanya keputusan skema (ID chapter stabil + `sourceType` + `bookKey`, bagian 6).

### Konsep umum

Format internal (**buku → chapter → paragraf → grup**) sudah dipakai di MVP untuk EPUB. Format lain cukup ditambah sebagai **importer baru** yang menghasilkan struktur yang sama. Reader, tap terjemahan, cache, dan Recap tidak perlu diubah.

```
EPUB ─────────┐
Luma Markdown ┼─► Importer ─► chapters + paragraphs + groups (Drift) ─► Reader / AI / Recap
PDF (nanti) ──┤
TXT (nanti) ──┘
```

### Skenario utama: baca buku fisik per chapter

Contoh: lagi baca Atomic Habits versi fisik.

1. Foto semua halaman chapter 3 (misal 10 foto)
2. **Di luar Luma**: kirim foto ke LLM (chat Claude/Gemini, atau nanti script) dengan prompt template di bawah → hasil file `.md` format Luma Markdown
3. Import `.md` ke Luma → buku "Atomic Habits" baru muncul di rak dengan satu chapter
4. Minggu depan lanjut chapter 7: foto → convert di luar → import `.md` → **otomatis masuk ke buku Atomic Habits yang sama**, terurut setelah chapter 3

Pembagian kerja: semua urusan foto, OCR, dan konversi ada **di luar app**. Luma hanya tahu cara import file Markdown yang sudah jadi.

### Format Luma Markdown (v1)

Satu file = satu chapter. Info buku dan chapter ada di frontmatter.

```markdown
---
luma: 1
book_key: atomic-habits
book: Atomic Habits
author: James Clear
chapter: 3
chapter_title: How to Build Better Habits in 4 Simple Steps
---

Paragraf pertama, utuh walaupun di buku aslinya terpotong
pindah halaman.

Paragraf kedua.

## Subjudul di dalam chapter

Paragraf setelah subjudul.

***

Paragraf setelah pemisah adegan.
```

Aturan:

| Elemen | Aturan |
|--------|--------|
| Frontmatter | `luma` (versi format), `book_key` (wajib, slug huruf kecil + strip), `book`, `author`, `chapter` (angka), `chapter_title` |
| Paragraf | Dipisah **satu baris kosong**. Baris yang tidak dipisah baris kosong = paragraf yang sama |
| Subjudul | `##` → `type = heading` |
| Pemisah adegan | `***` → `type = scene_break` |
| Format inline | Boleh `*miring*` dan `**tebal**`, selain itu teks polos |
| Dilarang | Nomor halaman, header/footer halaman, catatan "[gambar]" bebas tanpa aturan |

`book_key` adalah kunci pencocokan buku. Lebih aman daripada mencocokkan judul yang rawan beda tulisan.

### Logika import di Luma

1. Pilih file `.md` via `file_picker`
2. Parse frontmatter
3. **Tidak ada frontmatter** → tanya lewat UI: masuk ke buku mana (atau buat baru) + chapter berapa
4. `book_key` **belum ada** → buat buku baru (`sourceType = markdown`, cover default)
5. `book_key` **sudah ada** → tambahkan chapter ke buku itu
6. Nomor `chapter` **sudah ada** di buku itu → tanya: ganti atau batal. Kalau ganti: hapus chapter lama beserta `ai_results`-nya
7. Hitung `sortOrder` dari nomor chapter, sisipkan di posisi yang benar, hitung ulang `charOffset`
8. Parse body → paragraf → `assignGroups` → insert dalam satu transaksi
9. Toast: "Bab 7 masuk ke Atomic Habits ✨" (copy final menyesuaikan desain)

UI tambahan nanti:

- Daftar isi buku Markdown menampilkan bab yang belum ada secara samar, misal "Bab 4–6 belum ada"
- Progres baca per chapter (total buku tidak diketahui)
- Tombol "Tambah chapter" di halaman/aksi buku → langsung buka file picker dengan buku sudah terpilih

### Prompt template konversi foto (dipakai di luar app)

```
Kamu akan menerima foto halaman-halaman satu chapter dari buku fisik.
Ubah menjadi satu file Markdown dengan format persis seperti di bawah.

Aturan WAJIB:
1. Transkripsi PERSIS. Jangan memparafrase, meringkas, menerjemahkan,
   atau memperbaiki kata/ejaan dari buku.
2. Urutkan halaman berdasarkan nomor halaman yang tercetak, bukan urutan
   foto kalau berbeda.
3. Sambung paragraf yang terpotong antar halaman menjadi satu paragraf utuh.
4. Sambung kata yang terpotong tanda hubung (-) di ujung baris.
5. Buang nomor halaman, header, dan footer halaman.
6. Pisahkan paragraf dengan SATU baris kosong. Jangan memecah satu
   paragraf menjadi beberapa baris.
7. Subjudul di dalam chapter pakai "## ". Pemisah adegan pakai "***".
8. Miring pakai *teks*, tebal pakai **teks**. Selain itu teks polos.
9. Gambar/diagram: tulis satu baris "[Gambar: deskripsi singkat]" sebagai
   paragraf sendiri. Tabel: tulis isinya sebagai paragraf biasa.
10. Kalau ada bagian yang tidak terbaca, tulis [tidak terbaca], jangan
    menebak.

Isi frontmatter berikut (nomor dan judul chapter boleh kamu baca dari
halaman pertama chapter):

---
luma: 1
book_key: {book_key}
book: {judul buku}
author: {penulis}
chapter: {nomor chapter}
chapter_title: {judul chapter}
---

Balas HANYA dengan isi file Markdown, tanpa penjelasan lain.
```

Catatan:

- Kirim foto dalam satu percakapan sekaligus (atau per 3–5 foto lalu minta lanjutkan), supaya paragraf antar halaman bisa disambung.
- Pakai **`book_key` yang sama** untuk semua chapter dari buku yang sama. Simpan daftar `book_key` di catatan.
- Foto lebih bagus pakai document scanner (auto crop + luruskan perspektif), misal fitur scan di app Files/Notes iPhone.
- Cek cepat hasilnya sebelum import: risiko terbesar adalah LLM mengubah kata atau melewatkan paragraf.
- Nanti kalau sering dipakai: jadikan script kecil (mis. Python) yang memanggil OpenRouter dengan model vision (GLM 5.3 Flash / DeepSeek V4.1 Flash / Qwen 3.8 Flash menerima gambar) dan langsung menulis file `.md`.

### Opsi support PDF

| Jalur | Cara | Kelebihan | Kekurangan |
|-------|------|-----------|------------|
| 1. Convert di luar app | Marker / Docling (PDF → Markdown) lalu sesuaikan ke format Luma Markdown, atau Calibre (PDF → EPUB) | Nol kode tambahan, cocok untuk sekarang | Manual, hasil Calibre sering berantakan |
| 2. Parse di app | `pdfrx` ekstrak teks + heuristik (sambung baris, hapus hyphen, buang header/footer, deteksi paragraf dari jarak/indentasi) | Langsung dari HP | Banyak trial-error, tiap PDF bisa beda |
| 3. Parse dengan LLM | Kirim teks atau gambar halaman ke LLM, minta JSON paragraf | Bisa handle PDF scan, hasil rapi | Risiko teks berubah dari aslinya, perlu instruksi tegas |

Setelah importer Luma Markdown ada, jalur 1 jadi jalur default untuk PDF: PDF → Markdown di luar app → import.

### Format lain yang mungkin disupport

- **TXT**: paling gampang
- **HTML**: relatif mudah (EPUB pada dasarnya HTML)
- **MOBI / AZW3**: convert ke EPUB via Calibre dulu
- File dengan **DRM** tidak bisa diparse

### Urutan pengerjaan kasar (Iterasi 3)

1. Parser frontmatter + body Luma Markdown + unit test
2. Logika import: buku baru / tambah chapter / chapter duplikat
3. Sisip chapter + hitung ulang `sortOrder` & `charOffset`
4. UI: import `.md`, dialog tanpa frontmatter, dialog ganti chapter, toast
5. Daftar isi dengan bab bolong + progres per chapter
6. (Opsional) Script konversi foto → `.md` via OpenRouter

---

## 14. Catatan & Ide (raw)

_Tempat dump ide selama dogfooding. Triage seminggu sekali._

- **Bagian non-isi buku (Okt 2026, belum final).** Import cuma buang yang pasti bukan isi, dikenali dari struktur (bukan judul): lisensi Gutenberg, halaman daftar isi / indeks (kebanyakan isinya link), dan chapter kosong / cuma judul. Introduction, Notes, Appendix, Glossary, dan iklan penerbit tetep disimpen: salah buang = isi hilang + cache terjemahan ikut kehapus pas re-import, sedangkan kelebihan satu bab cuma nambah satu entri. Pantau pas dogfooding: kalau Introduction ganggu, opsinya buku dibuka langsung di bab isi pertama, bukan dibuang.
