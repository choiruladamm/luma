# Import Luma Markdown & PDF

> Status: **jalan** (#75 parser, #76 simpan ke DB, #77 UI, #80 kartu Rak; induk #79). PDF masuk lewat Markdown: panduan di bawah, uji dengan PDF asli di #78.

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
| Judul buku | `#` pertama; kalau tidak ada, nama file (`atomic-habits-bab3.md` → "Atomic Habits Bab3") |
| Judul bab | Heading pertama; kalau tidak ada, "Bab N" |
| Nomor bab | Angka di nama file (`bab3`, `chapter-07`, `ch12`); kalau tidak ada, bab terakhir buku itu + 1 (buku baru: 1) |
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

PDF tidak dibaca langsung. Convert ke Markdown di luar app, lalu import. **Belum diuji dengan PDF asli** (#78): hasil di bawah bergantung pada PDF-nya.

### Docling

Pasang sekali pakai tanpa install global lewat `uv`:

```bash
uvx --from docling docling buku.pdf --to md --output hasil/
```

Perintahnya `docling <sumber> --to md --output <folder>`. `--no-ocr` mempercepat kalau PDF-nya teks asli (bukan scan). Pertama kali jalan, Docling mengunduh model (cukup besar).

### Marker

Alternatif yang sama-sama mengubah PDF jadi Markdown. Cara pakainya belum diverifikasi di sini; cek dokumentasi resminya sebelum dipakai.

### Setelah convert

1. **Pecah per bab.** Luma menerima satu bab per file. Satu `.md` besar berisi seluruh buku masuk sebagai satu bab, jadi potong per bab dulu di editor, dan beri nama `bab-1-judul.md`, `bab-2-judul.md`, dst. supaya nomor bab ketebak dari nama file.
2. **Cek hasilnya.** Yang sering berantakan: nomor halaman dan header/footer ikut jadi paragraf, kata terpotong tanda hubung (`kon-\ntinu`), kolom ganda tercampur, daftar isi jadi paragraf. Parser membuang gambar, tabel, dan blok kode, tapi tidak bisa menebak sampah teks.
3. **(Opsional) frontmatter** di atas tiap file supaya sheet dilewati.
4. Import. Kalau satu bab kebanyakan sampah, buka file-nya, rapikan, lalu import ulang dengan nomor bab yang sama ("Ganti").

PDF scan tanpa teks butuh OCR; hasilnya paling riskan salah. Untuk PDF scan atau foto, [prompt template](#prompt-template-konversi-foto) ke LLM biasanya lebih rapi.

## Ditunda

- Daftar isi buku Markdown yang menampilkan bab bolong ("Bab 4–6 belum ada") dan progres per bab
- Tombol "Tambah bab" di menu buku (sekarang cukup lewat picker biasa)
- Tandai buku Markdown "kelar" manual
- Script konversi foto → `.md` lewat OpenRouter (model vision)
- Parse PDF langsung di dalam app (`pdfrx` atau LLM)
- Render miring/tebal
- TXT, HTML, MOBI/AZW3 (convert ke EPUB via Calibre dulu). File ber-DRM tidak bisa diparse.
