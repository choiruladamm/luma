# Data Model (Drift)

Prinsip: **file diparse sekali saat import** ke format internal. Reader, AI, dan Recap hanya membaca tabel di bawah, tidak pernah parse file ulang.

> **Keputusan penting: ID chapter stabil.** Chapter bisa masuk tidak berurutan (mis. import Markdown chapter 3, lalu 7, lalu 5; lihat [import-formats.md](ideas/import-formats.md)). Karena itu semua tabel lain menunjuk ke `chapters.id` (stabil), **bukan** ke posisi/urutan chapter. Urutan tampil diatur kolom `sortOrder`.

## `books`

| Kolom | Tipe | Catatan |
|-------|------|---------|
| id | int (PK) | |
| sourceType | text | `epub` (MVP) / `markdown` (nanti) |
| bookKey | text? (unique) | Slug untuk mencocokkan import Markdown ke buku yang sama (mis. `atomic-habits`). Null untuk EPUB |
| title | text | |
| author | text? | |
| fileName | text? | **Nama file saja**, bukan absolute path. Null untuk buku Markdown |
| coverName | text? | Nama file cover. Null → pakai cover default |
| originalTitle | text? | Judul asli EPUB, diisi sekali pas edit pertama. Null = belum pernah diedit. `title` / `author` tetap nilai yang **tampil** |
| originalAuthor | text? | Penulis asli EPUB. Null + `originalTitle` terisi = aslinya tanpa penulis |
| useDefaultCover | bool (default false) | true = cover EPUB disembunyiin (repository ngasih `coverName` null ke UI). `coverName` tetap utuh di DB + disk |
| hash | text? (unique) | SHA-256 isi file EPUB, untuk cegah import dobel |
| parserVersion | int | Versi logika parsing + grouping. Naik → re-import & invalidasi cache buku itu |
| totalChars | int | Untuk hitung persentase baca (hanya bermakna untuk buku lengkap) |
| createdAt | datetime | |
| lastOpenedAt | datetime? | Untuk urutan rak |
| firstOpenedAt | datetime? | Pertama kali dibuka. Diisi sekali, gak berubah lagi |
| readingSeconds | int (default 0) | Total waktu baca aktif, ditampilkan di layar akhir buku ("6 jam 20 mnt", atau "45 mnt" di bawah 1 jam). Tetap dipertahankan walau ada `reading_sessions` (ditulis satu transaksi sama sesinya) |
| finishedAt | datetime? | Pertama kali layar akhir buku kebuka. Diisi sekali, gak ditimpa. Sengaja gak disimpulin dari sesi: lompat ke bab terakhir bisa ngelabuin |

**Ubah judul & penulis** ([#69](https://github.com/choiruladamm/luma/issues/69)): `updateMetadata` nyimpen nilai asli ke `original*` sekali, hasil edit yang sama persis dengan aslinya nge-null-in `original*` lagi. Re-import **gak boleh nimpa** `title` / `author` kalau `originalTitle != null`; yang diperbarui `originalTitle` / `originalAuthor`. Judul gak masuk kunci cache AI, jadi `promptVersion` gak naik.

**Waktu baca aktif** dihitung selama halaman baca kebuka dan app di foreground. Berhenti kalau 2 menit gak ada scroll/tap (2 menit itu ikut dihitung), lanjut lagi pas ada interaksi. Disimpan bertahap (tiap scroll berhenti, pindah bab, app ke background, keluar halaman baca), jadi app yang dimatiin iOS cuma kehilangan beberapa detik terakhir.

## `chapters`

| Kolom | Tipe | Catatan |
|-------|------|---------|
| id | int (PK, autoincrement) | **Kunci stabil**, dipakai tabel lain |
| bookId | int (FK) | |
| sortOrder | int | Urutan tampil. EPUB: urutan TOC. Markdown: dari nomor chapter |
| chapterNumber | int? | Nomor bab asli dari buku (untuk Markdown / daftar isi) |
| title | text | Dari TOC/nav EPUB, fallback "Bab N" |
| charOffset | int | Jumlah karakter sebelum chapter ini (untuk persentase). Dihitung ulang kalau ada chapter disisipkan |

Index: `(bookId, sortOrder)`.

## `paragraphs`

| Kolom | Tipe | Catatan |
|-------|------|---------|
| chapterId | int (FK → chapters.id) | |
| paragraphIndex | int | Urutan dalam chapter |
| groupIndex | int? | Grup untuk tap/AI. Null untuk heading & pemisah adegan (tidak bisa di-tap) |
| type | text | `paragraph` / `heading` / `scene_break` |
| text | text | Teks polos yang sudah dinormalisasi |

Unique key: `(chapterId, paragraphIndex)`. Index tambahan: `(chapterId, groupIndex)`.

## `reading_progress`

| Kolom | Tipe | Catatan |
|-------|------|---------|
| bookId | int (PK) | |
| chapterId | int (FK) | |
| paragraphIndex | int | Paragraf paling atas yang keliatan di bawah safe area atas |
| paragraphOffset | real (default 0.0) | Bagian paragraf itu yang udah lewat garis atas, **fraksi tinggi paragraf** 0.0–1.0 (bukan piksel, biar tetep pas kalau font/ukuran/jarak baris diganti di Aa). Di-clamp 0–1 pas nyimpen dan pas baca |
| updatedAt | datetime | |

## `ai_results`

| Kolom | Tipe | Catatan |
|-------|------|---------|
| chapterId | int (FK) | |
| groupIndex | int | |
| translations | text | JSON array string, satu item per paragraf di grup (urut) |
| meaning | text | Satu penjelasan untuk seluruh grup |
| model | text | Model yang dipakai |
| promptVersion | int (default 1) | `aiPromptVersion` waktu dibikin. Lebih lama dari yang sekarang = dianggap belum ada (`find` balikin null), grupnya diterjemahin ulang pas dibuka dan barisnya ditimpa. Penanda di margin & hitungan di Pengaturan tetap ngitung semua baris |
| createdAt | datetime | |
| openCount | int (default 0) | Berapa kali hasil ini dibuka (penanda grup yang sering dibaca ulang). Disimpan = 1; tiap sheet Artinya kebuka dari cache +1; nimpa hasil prompt versi lama ngulang dari 1. Baris sebelum schema 5 mulai dari 0 |
| lastOpenedAt | datetime? | Terakhir dibuka |

Unique key: `(chapterId, groupIndex)`.

## `ai_breakdowns`

Cache Bedahin per grup (#62). Dibuka lagi = langsung tampil, gak motong saldo.

| Kolom | Tipe | Catatan |
|-------|------|---------|
| chapterId | int (FK → chapters.id, cascade) | Re-import / hapus buku ikut kehapus |
| groupIndex | int | |
| body | text | Teks mentah balasan model yang udah lolos `parseBreakdown`. Di-parse ulang pas dibaca, jadi parser jadi satu-satunya sumber kebenaran |
| sourceHash | text | `breakdownSourceHash` (SHA-256 JSON `translations`) dari `ai_results` yang dipake. Beda = dianggap belum ada: terjemahannya udah diganti, rentang `K` gak berlaku lagi |
| model | text | |
| promptVersion | int | `breakdownPromptVersion`. Lebih lama = dianggap belum ada, dibedah ulang pas dibuka, baris ditimpa |
| createdAt | datetime | |

Unique key: `(chapterId, groupIndex)`.

## `reading_sessions`

Log append-only potongan waktu baca aktif. Statistik (streak, heatmap, kecepatan baca) dihitung lewat query dari sini; gak ada tabel rollup. Gak ada backfill: waktu baca sebelum tabel ini cuma ada sebagai total `books.readingSeconds`.

| Kolom | Tipe | Catatan |
|-------|------|---------|
| id | int (PK, autoincrement) | |
| bookId | int (FK → books.id, cascade) | |
| chapterId | int (FK → chapters.id, cascade) | Satu potongan gak pernah lintas bab: pindah bab selalu nyimpen dulu, jadi lompat lewat daftar isi gak ikut keitung sebagai karakter terbaca |
| startedAt | datetime | Hari dihitung lokal (`localtime`) di query |
| seconds | int | Waktu aktif (`ReadingClock`, idle 2 menit) |
| startChar | int | Posisi absolut di buku (karakter) di awal potongan |
| endChar | int | Di akhir potongan. Dua ujung disimpen, bukan satu angka `charsRead`: aturan "berapa yang dianggap beneran dibaca" (batas kecepatan wajar) ada di query, bisa diganti tanpa ngubah data |

Index: `(bookId, startedAt)`, `(startedAt)`.

**Pengisian (#44).** Titik tulisnya sama kayak total waktu baca (pindah bab, app ke background, keluar halaman baca, scroll berhenti), satu transaksi sama `books.readingSeconds`. `startedAt` = waktu simpan dikurangi `seconds`. Posisi karakter dari `charPosition` (`charOffset` bab + fraksi scroll × panjang bab, sumber yang sama dengan garis progres). Pindah bab nyimpen potongan bab lama **sebelum** state diganti, jadi potongan gak pernah lintas bab. Potongan yang nyambung digabung ke baris terakhir (bab sama, `startChar` = `endChar` baris itu, jeda < 2 menit), maksimal sampai 5 menit per baris biar jam favorit tetep ke-resolve per jam, bukan semuanya ke jam mulai baca.

## `ai_calls`

Log append-only request LLM, terpisah dari cache `ai_results` (`createdAt`-nya ke-reset tiap retranslate, barisnya ikut kehapus pas re-import). Dasar statistik biaya, bantuan AI per 1.000 karakter, dan bab tersulit. Cache hit gak nulis baris. Pengisiannya di #47 (ditunda, Okt 2026: statistik AI jadi raw idea, tabelnya kosong dulu).

| Kolom | Tipe | Catatan |
|-------|------|---------|
| id | int (PK, autoincrement) | |
| bookId | int? (FK → books.id, set null) | `set null` supaya biaya bulanan gak berubah waktu buku dihapus |
| chapterId | int? (FK → chapters.id, set null) | |
| groupIndex | int? | |
| kind | text | `group` (terjemahan + makna). Recap ([recap.md](ideas/recap.md)) nanti nambah nilai |
| model | text | |
| promptVersion | int | |
| chars | int | Panjang teks target, penyebut "per 1.000 karakter" |
| promptTokens, completionTokens | int? | Null = model gak ngirim `usage` |
| costUsd | real? | Dari `usage` OpenRouter. Null = gak tercatat (tampilin "gak tercatat", bukan 0) |
| firstTokenMs, totalMs | int? | Latensi |
| error | text? | `AiError.name`. Null = sukses |
| createdAt | datetime | |

> ⚠️ **Indeks paragraf dan grup harus stabil.** Logika parsing dan grouping jangan diubah sembarangan setelah ada data. Kalau harus berubah, naikkan `parserVersion`, re-import buku, dan hapus `ai_results` buku tersebut.

## Versi schema & migrasi

| Versi | Perubahan |
|-------|-----------|
| 1 | Awal |
| 2 | `books.firstOpenedAt`, `books.readingSeconds` |
| 3 | `reading_progress.paragraphOffset` |
| 4 | `ai_results.promptVersion` (baris lama = 1, prompt sebelum #40) |
| 5 | Pencatatan statistik (#42): tabel `reading_sessions` + `ai_calls`, `books.finishedAt`, `ai_results.openCount` + `lastOpenedAt`. Tabel baru kosong, baris lama `openCount` = 0 |
| 6 | Tabel `ai_breakdowns` (Bedahin, #62). Data lama gak disentuh |
| 7 | `books.originalTitle`, `originalAuthor`, `useDefaultCover` (ubah judul + penulis, #69). Baris lama: `null`, `null`, `false` |

Tiap ubah tabel: naikkan `schemaVersion`, tambah langkah di `onUpgrade`, dan test migrasi dari versi sebelumnya (data tetap utuh, schema hasil migrasi sama dengan install baru). Restore backup dari schema lama ikut dimigrasi saat database dibuka ([backup.md](backup.md)).

## Pengaturan

API key di `flutter_secure_storage` (Keychain di iOS, Keystore di Android). Model ID, preferensi Aa, dan backup terakhir di tabel `settings` sederhana (key-value) di Drift, supaya ikut ter-backup. Model LLM: `ai.model` (model ID OpenRouter, default `z-ai/glm-5.3-flash`; pilihan dari daftar kandidat di [llm.md](llm.md)). API key di Keychain / Keystore dengan kunci `openrouter_api_key`, cuma disimpen setelah lolos cek bentuk dan cek ke OpenRouter ([llm.md](llm.md)); kosong = dihapus. "Hapus cache" di Pengaturan = kosongin `ai_results` + `ai_breakdowns` setelah konfirmasi; Pengaturan nampilin jumlah paragraf yang udah diterjemahin + ukuran teksnya. Backup terakhir: `backup.lastAt` (ISO 8601), `backup.lastName`, `backup.lastSize` (byte). Kunci Aa: `reader.size` (indeks step 0–6), `reader.font`, `reader.spacing`, `reader.margin`, `theme` (nama enum), `reader.hideStatusBar`, `reader.showProgressLine` (`true`/`false`). Urutan rak: `shelf.sort` (`lastOpened` / `title` / `added`, default `lastOpened`). Tampilan rak: `shelf.view` (`grid` / `list`, default `grid`). Hindari `shared_preferences` untuk data yang perlu ikut backup.
