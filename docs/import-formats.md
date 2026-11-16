# Import Luma Markdown & PDF

Induk Markdown: [#79](https://github.com/choiruladamm/luma/issues/79); uji PDF asli lewat jalur ini: #78. PDF bisa masuk lewat Markdown (panduan di bawah) atau langsung ([Import PDF langsung](#import-pdf-langsung)).

## Konsep umum

Format internal (**buku → chapter → paragraf → grup**) dipakai EPUB dan Markdown. Importer baru cuma menghasilkan struktur yang sama, jadi reader, tap terjemahan, cache, dan Bedahin tidak berubah.

```
EPUB ─────────────────────────┐
Luma Markdown (.md) ──────────┼─► chapters + paragraphs + groups (Drift) ─► Reader / AI
PDF ─► Docling/Marker ─► .md ─┘
```

Semua urusan foto, OCR, dan konversi PDF ada **di luar app**. Luma hanya tahu cara import file Markdown.

## Skenario

**Baca buku fisik per chapter.** Foto halaman chapter 3 → kirim ke LLM dengan prompt template di bawah → file `.md` → import. Minggu depan chapter 7: ulangi, otomatis masuk ke buku yang sama, terurut setelah chapter 3.

**Baca PDF.** PDF → Docling → `.md` per bab → import (lihat [Import PDF](#import-pdf)).

## Format

Satu file = satu chapter. **Frontmatter opsional.**

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

## Subjudul di dalam chapter

Paragraf setelah subjudul.

***

Paragraf setelah pemisah adegan.
```

### Frontmatter

Dianggap frontmatter kalau baris pertama `---`, ada `---` penutup, dan semua baris di antaranya `kunci: nilai`. Selain itu `---` di awal file dibaca sebagai pemisah adegan.

| Kunci | Aturan |
|-------|--------|
| `book_key` | Slug huruf kecil, angka, strip (`atomic-habits`). Kunci pencocok buku. Salah → error "Nama bukunya gak valid" |
| `chapter` | Angka. Bukan angka → error "Nomor babnya gak kebaca" |
| `book`, `author`, `chapter_title` | Opsional |
| `luma` | Versi format, diabaikan |

`book_key` **dan** `chapter` ada → langsung import, tanpa sheet. Selain itu sheet "Masuk ke buku mana?" muncul.

### Body

Parser toleran sama Markdown umum, supaya hasil konversi PDF langsung kebaca.

| Elemen | Hasil |
|--------|-------|
| Teks dipisah **baris kosong** | Satu paragraf. Baris yang menyambung digabung jadi satu paragraf |
| `#` sampai `######` | `heading` |
| `***`, `---`, `* * *`, `___` | `scene_break` |
| Item list (`- `, `1. `) | Tiap item satu paragraf |
| Kutipan `>`, `**tebal**`, `*miring*`, `` `kode` ``, `[teks](url)` | Dilepas, teksnya disimpan (`paragraphs.text` teks polos, sama kayak EPUB) |
| Gambar `![..](..)`, tabel `\|`, blok kode | Dibuang |

Tidak ada satu pun paragraf bacaan (cuma heading, atau kosong) → error "Filenya kosong nih".

### Tebakan tanpa frontmatter

| Field | Tebakan |
|-------|---------|
| Judul buku | `#` pertama; kalau tidak ada, nama file tanpa token bab (`bab-1-deep-work.md` dan `deep-work-bab3.md` → "Deep Work") |
| Judul bab | Heading pertama; kalau tidak ada, "Bab N" |
| Nomor bab | Angka di nama file (`bab3`, `chapter-07`, `ch12`; "ch" di tengah kata seperti `catch-22` tidak dihitung); kalau tidak ada, bab terakhir buku itu + 1 (buku baru: 1) |
| `book_key` | Slug dari judul buku (judul tanpa huruf latin: penanda waktu) |

Semua boleh diubah di sheet.

## Logika import

Satu transaksi:

1. Buku tujuan: dipilih di sheet, atau dicari lewat `book_key`. Belum ada → buku baru (`sourceType = markdown`, cover default). Buku EPUB tidak pernah jadi tujuan.
2. Nomor bab kosong → bab terakhir + 1.
3. Nomor bab **sudah ada** → `ChapterExists`; UI tanya. Kalau diganti, bab ditimpa **di tempat**: id bab tetap, jadi sesi baca dan statistik aman. Yang dibuang: paragraf lama, `ai_results`, `ai_breakdowns` bab itu. Posisi baca di bab itu balik ke paragraf 0.
4. Paragraf → `assignGroups` ([grouping.md](grouping.md)) → insert.
5. `sortOrder` (dari nomor bab), `charOffset` semua bab, dan `books.totalChars` dihitung ulang.

File `.md` **tidak disimpan** (`hash` dan `fileName` null): isinya sudah di Drift dan ikut backup. Import ulang file yang sama = bab dobel, bukan duplikat buku.

Buku Markdown **tidak pernah "Kelar!"** (`finishedAt` tidak diisi): total bab tidak diketahui, bab terakhir yang ada belum tentu akhir buku.

## UI

Semua di atas Rak, tanpa layar baru. Desain: board "Import Markdown" (Stabilo).

- **Sheet "Masuk ke buku mana?"**: radio list ("Buku baru" + buku Markdown yang ada), field Judul buku / Judul bab / Nomor bab keisi tebakan.
- **Dialog bab dobel** ("Bab 7 udah ada"): Ganti menampilkan spinner sampai selesai; Batal balik ke sheet dengan isian utuh.
- **Toast** "Bab 7 masuk ke Atomic Habits ✨" + Baca (buka bab yang barusan masuk). 5 detik.
- **Error**: file kosong, nomor bab gak kebaca, nama buku gak valid, file gak kebaca.
- **Kartu Rak**: strip bab (1 slot per nomor bab; bab belum masuk garis putus), chip "N bab" gantiin persen. Nomor tertinggi > 16 → satu bar. Bab di bawah posisi baca dianggap sudah dibaca.

## Prompt template konversi foto

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

## Import PDF

PDF tidak dibaca langsung. Convert ke Markdown di luar app, lalu import.

Jalur ini diuji dengan **PDF buatan sendiri** (4 halaman, 2 bab, ada header halaman dan nomor halaman), bukan PDF terbitan asli. Layout asli (kolom ganda, catatan kaki, scan) hampir pasti lebih berantakan; catat temuannya di [ideas/raw.md](ideas/raw.md).

### Docling

Pasang sekali pakai tanpa install global lewat `uv`:

```bash
uvx --from docling docling buku.pdf --to md --output hasil/
```

Perintahnya `docling <sumber> --to md --output <folder>`. `--no-ocr` mempercepat kalau PDF-nya teks asli (bukan scan). Pertama kali jalan, Docling mengunduh model (cukup besar).

### Marker

Alternatif yang sama-sama mengubah PDF jadi Markdown. Cara pakainya belum diverifikasi di sini; cek dokumentasi resminya sebelum dipakai.

### Yang kejadian di uji Docling

- **Satu PDF = satu `.md`.** Dua bab keluar bersambung di satu file, tidak dipisah.
- **Header halaman yang berulang jadi heading `##`** (judul buku, 3 kali, satu muncul di tengah adegan). Hapus manual.
- **Nomor halaman hilang sendiri.**
- Pemisah adegan keluar `* * *` (terbaca), list jadi `- `, miring/tebal hilang.
- **Tanpa `#`**: semua heading `##`, jadi judul buku ditebak dari nama file, bukan dari isi.

### Setelah convert

1. **Pecah per bab.** Luma menerima satu bab per file. Satu `.md` besar berisi seluruh buku masuk sebagai satu bab, jadi potong per bab dulu di editor, dan beri nama `bab-1-judul-buku.md`, `bab-2-judul-buku.md`, dst. Nomor bab dan judul buku (bagian setelah "bab-N") ketebak dari nama file, jadi semua bab otomatis masuk ke buku yang sama.
2. **Cek hasilnya.** Yang sering berantakan: header/footer berulang ikut jadi paragraf atau heading, kata terpotong tanda hubung (`kon-\ntinu`), kolom ganda tercampur, daftar isi jadi paragraf. Parser membuang gambar, tabel, dan blok kode, tapi tidak bisa menebak sampah teks.
3. **(Opsional) frontmatter** di atas tiap file supaya sheet dilewati.
4. Import. Kalau satu bab kebanyakan sampah, buka file-nya, rapikan, lalu import ulang dengan nomor bab yang sama ("Ganti").

PDF scan tanpa teks butuh OCR; hasilnya paling riskan salah. Untuk PDF scan atau foto, [prompt template](#prompt-template-konversi-foto) ke LLM biasanya lebih rapi.

## Import PDF langsung

Induk: [#83](https://github.com/choiruladamm/luma/issues/83). Jalur Docling tetap jadi cadangan (scan, layout rumit).

**Hasil korpus (#89, 8 Nov 2026, macOS `flutter test` via `tool/pdf_probe.dart`, bukan angka device).**

| PDF | Halaman | Bab | Catatan |
|---|---|---|---|
| Novel nonfiksi 1 kolom (Atomic Habits) | 256 | 24, sesuai bookmark | Paragraf utuh, tanpa nomor halaman nyelip. Daftar isi ebook (tanpa nomor halaman) ikut jadi isi bab "Epigraph" |
| Nonfiksi + catatan (The First 20 Hours) | 331 | 16, sesuai bookmark | 5 halaman tanpa teks (cover/ilustrasi) dilewati; hyphen akhir baris jadi gabung (`three-` + `character` → `threecharacter`) |
| Buku besar dengan "Letters" sebagai satu bookmark (Letters from a Stoic) | 312 | 51 | Bookmark raksasa dipecah ke anak-anaknya; surat tanpa bookmark ikut surat sebelumnya |
| Jurnal 2 kolom (systematic review) | 15 | 5 | Halaman 1 (kotak sitasi di samping) campur aduk; sisanya kebaca; header/footer berulang dibuang |
| Dokumen teknis (system card) | 153 | 16 | Beberapa bookmark aneh jadi bab kecil; tabel jadi paragraf pendek |

Waktu (macOS, bukan benchmark): ekstraksi 0,5–1,6 dtk, layout 0,7 dtk untuk 250–330 halaman. Simulator iPhone 17 (iOS 27, build debug Luma Dev): pilih PDF 331 halaman dari Files → progres → rak (cover, 17 bab) → baca bab → duplikat membuka sheet "udah ada di rak" → progres baca tersimpan.

**Yang ditemukan dan diperbaiki dari korpus:** kotak huruf PDFium itu *ketat* (titik kecil, `h` lebih tinggi dari `a`), jadi pengelompokan baris pakai geometri memecah satu baris jadi banyak. Sekarang layout memakai pemisah baris + spasi dari PDFium sendiri; ukuran font = persentil 80 tinggi huruf; batas paragraf pakai jarak baseline, lebar huruf, dan lebar kolom, bukan konstanta.

**Error nyata (PDFium asli, PDF buatan `gs`/`cupsfilter`, `tool/pdf_import_check.dart`):** scan (12/12 halaman tanpa teks) → `scan`; `-sUserPassword` → `password`; 3 KB byte acak `.pdf` → `corrupt`; separuh scan separuh teks → masuk dengan `skipped=12`.

**Perilaku tambahan hasil analisis korpus.** Catatan kaki (digit naik dari baseline) dibuang dari baris; paragraf sampah dari gambar/diagram (`nn nn n`, satu huruf, angka halaman polos) dibuang (sampah pendek 80 → 11 per buku); heading di awal bab yang cuma mengulang judul bab dibuang; daftar isi tanpa nomor halaman dicocokkan per kata (`1 | Judul` vs `1 Judul`), termasuk yang barisnya menyatu; spasi hilang antar-run PDFium disisipkan (kutip/apostrof dikecualikan); tanpa pemisah baris PDFium, baris dikelompokkan per baseline; baris dibentuk per halaman di service (puncak RSS 334 → 275 MB di macOS, layout 1 dtk → 0,15 dtk); salinan sementara picker dibersihkan abis import; judul dari nama file dibersihkan (`_`, spasi dobel, `(z-lib.org)`).

**Perilaku tambahan hasil uji Atomic Habits + Letters di device.** Spasi hilang antar-run beda ukuran ("THE FATE OF" huruf kapital kecil + "British") disisipkan memakai ukuran lokal; bab front matter bookmark yang cuma label dan kurang dari 1500 karakter (Title Page, Copyright Page, Contents, Cover) dibuang; daftar isi yang tertanam di bab lain (4+ blok pendek berurutan yang kebanyakan judul bab) dibuang; judul lengkap diambil dari baris pertama huruf kapital yang memuat heading ("LETTERS FROM A STOIC", bukan "FROM A STOIC"). Metrik korpus tanpa regresi.

**Batas yang diketahui:** judul/penulis dari metadata PDF belum kebaca (pdfrx 2.12 tanpa API-nya; judul = heading pertama di 5 halaman awal yang bukan label front matter, lalu nama file, jadi PDF yang halaman judulnya bukan heading tampil sebagai nama file), halaman dengan kotak samping / kolom tak sama lebar / 3+ kolom (#94; rencana dan contoh jurnal MDPI halaman 1 dicatat di issue itu), tabel, huruf kecil kapital di awal bab, daftar isi yang barisnya tergabung jadi satu paragraf. Daftar isi tanpa nomor halaman dibuang kalau barisnya mengutip judul bab lain. Hyphen akhir baris dibuang, kecuali setelah kepala kata majemuk (`two-`, `three-`, `self-`, ...). Belum diuji: Android, rotasi/spread, tap Artinya di paragraf PDF (butuh panggilan AI).

Pilih `.pdf` di picker, langsung jadi satu buku utuh, tanpa Docling.

### Keputusan

| Keputusan | Pilihan | Alasan |
|---|---|---|
| Engine | `pdfrx` (PDFium, MIT, iOS + Android) | Teks + posisi per huruf (`loadStructuredText`), outline/bookmark, render halaman buat cover. Syncfusion lisensinya komersial, PDFKit cuma iOS |
| Ekstraksi | Heuristik di device, bukan LLM | Gratis, offline, teks gak diubah. LLM berisiko parafrase, mahal satu buku penuh, lambat |
| Model buku | Satu PDF = satu buku utuh, kayak EPUB | `finishedAt` dan cek dobel lewat hash jalan |
| `SourceType` | Tambah `pdf` | Kolom `textEnum`: schema gak berubah, tanpa migrasi |
| File asli | Disimpen (`$hash.pdf`), ikut backup (`books/`) | Heuristik bakal sering di-tuning: naikin versi parser + re-import tanpa minta file lagi (re-import PDF rencana, belum ada kodenya) |
| Versi parser | `pdfParserVersion` terpisah, disimpan di `books.parserVersion` | Tuning PDF gak maksa re-import EPUB |
| Jalur Docling | Tetap ada | PDF scan / layout rumit |

### Arsitektur

```
picker (.pdf) ─► ImportRepository.importPdf
   1. hash → cek dobel
   2. PdfService (pdfrx, worker PDFium-nya sendiri)
        → per halaman: huruf → baris langsung (huruf halaman dibuang; satu buku gak numpuk di memori)
        → outline (bookmark → halaman), metadata, render halaman 1 → cover
   3. Isolate.run(layout + pecah bab)   ← Dart murni, gak tau pdfrx
        → List<ParsedChapter> (paragraf + assignGroups)
   4. simpan file + _insert (jalur EPUB, sourceType: pdf)
```

PDFium gak thread-safe dan pdfrx udah jalanin di worker sendiri, jadi logika layout dipisah ke `lib/domain/pdf_layout.dart` + `pdf_chapters.dart`: dites pakai fixture baris, tanpa PDF dan tanpa native lib. File baru: `lib/data/services/pdf_service.dart` + dua file domain itu.

### Pipeline layout

1. **Baris dari huruf**, dikelompokkan per baseline, urut per **posisi** (bukan urutan stream; ada PDF yang stream-nya acak).
2. **Bersihin karakter**: ligatur (`ﬁ ﬂ ﬀ`) jadi huruf biasa; soft hyphen, `\u0000`, `�`, zero-width dibuang; NBSP jadi spasi.
3. **Kolom**: histogram x per baris; celah vertikal konsisten di tengah = dua kolom, kiri dulu baru kanan.
4. **Header/footer**: baris di pita atas/bawah (~8% tinggi halaman) yang teksnya (tanpa angka) berulang di ≥ 30% halaman dibuang. Nomor halaman polos (`12`, `xii`, `- 12 -`) dibuang.
5. **Font badan** = modus tinggi huruf, dibobot jumlah karakter.
6. **Catatan kaki**: baris bawah dengan font < 0.85× badan yang diawali angka dibuang; angka superscript di badan (lebih kecil dan naik) dibuang.
7. **Heading**: baris dengan font ≥ 1.2× badan, atau pola `Chapter N` / `Bab N` / `Part`. Drop cap (satu huruf besar) digabung ke baris berikutnya.
8. **Paragraf baru** kalau jarak antarbaris > 1.5× spasi normal, ada indent baris pertama, atau baris sebelumnya pendek (< 80% lebar) dan berakhiran `.?!"”`.
9. **Sambung antarhalaman**: akhir halaman tanpa tanda titik + halaman berikut diawali huruf kecil = satu paragraf.
10. **Tanda hubung**: `kon-` + `tinu` (huruf kecil) jadi `kontinu`; huruf besar / angka setelahnya = hubung dipertahankan.
11. **Pemisah adegan**: `* * *`, `***`, `---`, `- - -`, `___`, `• • •`, `###`, atau celah vertikal besar tanpa teks jadi `scene_break`.

### Pecah bab

1. **Outline PDF**: pilih level yang masuk akal (level atas isinya Part I/II → turun satu level). Bab mulai di halaman tujuan bookmark; mulai di tengah halaman dicari lewat heading yang cocok judul bookmark.
2. **Heading terbesar** di awal halaman, atau pola `Chapter|Bab N`.
3. **Fallback** per ~20 halaman ("Bagian 1, 2, ..."), biar gak jadi satu bab raksasa.

Lalu aturan non-isi yang sama kayak EPUB ([raw.md](ideas/raw.md)): bab kosong dan halaman daftar isi / indeks (baris berakhiran nomor halaman / titik-titik) dibuang, sisanya disimpen.

### Edge case

| Kasus | Penanganan |
|---|---|
| Ber-password | Error "PDF-nya dikunci password" (input password ditunda, #90) |
| PDF scan (> 50% halaman tanpa teks) | Error "PDF ini hampir gak ada teksnya" + arahan ke prompt foto / Docling |
| Campuran scan + teks | Halaman tanpa teks dilewati, toast nyebut jumlahnya |
| Rusak / bukan PDF | `PdfImportException` (`PdfImportError`: password, scan, corrupt, notPdf, empty, io), pola `EpubException`. Cancel = `ImportCancelled` |
| PDF yang sama | Cek hash → buka buku lama |
| Besar (500+ halaman, 100MB+) | `openFile(path)`, bukan bytes; teks dilepas per halaman; progres per halaman; bisa dibatalin |
| Dua kolom | Langkah 3. Tiga kolom ke atas gak dijamin (#94), arahkan ke Docling |
| Landscape / terputar / spread 2-up | Normalisasi rotasi halaman; spread dibaca sebagai dua kolom |
| Puisi, dialog, list | Baris pendek bisa kepecah jadi banyak paragraf; diterima, grouping tetap gabung yang pendek |
| Tabel, angka | Baris yang mayoritas angka/simbol dibuang; caption gambar tetap ikut |
| RTL / CJK / teks vertikal | Di luar scope |
| Judul / penulis | Judul: heading pertama di 5 halaman awal yang bukan label front matter (Copyright, Daftar isi, dst) → nama file. Penulis: null. **Deviasi:** pdfrx 2.12 gak punya API metadata, jadi judul/penulis metadata belum kebaca; tambah kalau pdfrx nyediain, bukan FFI langsung |
| Cover | Render halaman 1; gagal = cover default |
| Tuning nanti | Naikin `pdfParserVersion`, re-import dari file tersimpan, hapus `ai_results` buku itu (rencana, belum ada kodenya: `import_repository.dart` baru backfill EPUB) |
| `finishedAt` | `reading_progress_repository.dart` sudah mencakup PDF, cuma Markdown yang dilewat |
| Backup / restore | `$hash.pdf` ikut `books/`; cek restore gak cuma nerima `.epub` |
| Ukuran app | PDFium nambah ~5–8MB per arsitektur, diukur di spike |

### UI

Tanpa layar baru. Picker nerima `pdf`; sheet import EPUB dipakai ulang dengan copy "Lagi ngebongkar PDF" (tahap sama); error password / scan / rusak / kosong; kartu Rak = tampilan EPUB (persen).

### Test

- `test/domain/pdf_layout_test.dart`: fixture baris sintetis, satu kasus per langkah pipeline.
- `test/domain/pdf_chapters_test.dart`: outline, heading, fallback, buang daftar isi.
- `test/data/`: `importPdf` dengan `PdfService` palsu, cek dobel, rollback, `sourceType`.
- Widget test picker / sheet: service palsu, gak sentuh pdfrx / Drift.
- Korpus manual 5–8 PDF asli (gak di-commit): novel satu kolom, nonfiksi + catatan kaki, jurnal dua kolom, scan, ber-password, tanpa bookmark. `tool/pdf_probe.dart` dump hasil ke `.md` buat dicek mata (#89).

### Ditunda (dibuka kalau korpus nunjukin perlu)

- Input password ([#90](https://github.com/choiruladamm/luma/issues/90))
- OCR di device buat PDF scan ([#91](https://github.com/choiruladamm/luma/issues/91))
- Rapikan hasil pakai LLM ([#92](https://github.com/choiruladamm/luma/issues/92))
- Preview bab sebelum simpan ([#93](https://github.com/choiruladamm/luma/issues/93))
- Layout 3+ kolom ([#94](https://github.com/choiruladamm/luma/issues/94))

## Ditunda

- Daftar isi buku Markdown yang menampilkan bab bolong ("Bab 4–6 belum ada") dan progres per bab ([#95](https://github.com/choiruladamm/luma/issues/95))
- Tombol "Tambah bab" di menu buku, sekarang cukup lewat picker biasa ([#96](https://github.com/choiruladamm/luma/issues/96))
- Tandai buku Markdown "kelar" manual ([#97](https://github.com/choiruladamm/luma/issues/97))
- Script konversi foto → `.md` lewat OpenRouter, model vision ([#98](https://github.com/choiruladamm/luma/issues/98))
- Buang header Docling berulang + skrip pecah `.md` per bab ([#110](https://github.com/choiruladamm/luma/issues/110))
- Parse PDF langsung di dalam app: lihat [Import PDF langsung](#import-pdf-langsung) ([#83](https://github.com/choiruladamm/luma/issues/83))
- Render miring/tebal ([#99](https://github.com/choiruladamm/luma/issues/99))
- TXT, HTML, MOBI/AZW3; sementara convert ke EPUB via Calibre ([#100](https://github.com/choiruladamm/luma/issues/100)). File ber-DRM tidak bisa diparse.
