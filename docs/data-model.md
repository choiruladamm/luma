# Data Model (Drift)

Prinsip: **file diparse sekali saat import** ke format internal. Reader, AI, dan Recap hanya membaca tabel di bawah, tidak pernah parse file ulang.

> **Keputusan penting: ID chapter stabil.** Chapter bisa masuk tidak berurutan (mis. import Markdown chapter 3, lalu 7, lalu 5; lihat [import-formats.md](import-formats.md)). Karena itu semua tabel lain menunjuk ke `chapters.id` (stabil), **bukan** ke posisi/urutan chapter. Urutan tampil diatur kolom `sortOrder`.

## `books`

| Kolom | Tipe | Catatan |
|-------|------|---------|
| id | int (PK) | |
| sourceType | text | `epub` / `markdown` |
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
| contentRevision | int (default 1) | Snapshot isi/urutan untuk Book Chat. Metadata tidak menaikkan revision; append/replace/reorder Markdown menaikkan revision atomik lewat `AppDatabase.contentChanged` (#119) |
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
| section | text? | Label induk TOC EPUB bersarang, luar → dalam, dipisah ` › ` ("Discourses › Book I"). Null = belum diperiksa (buku dari schema ≤ 10), `''` = diperiksa, level teratas. Diisi saat import; buku lama di-backfill dari EPUB tersimpan saat chat buku dibuka (`ImportRepository.backfillSections`): cocok jumlah + judul → isi section dan judul TOC lengkap, tidak cocok/file hilang → `''`. Paragraf tidak disentuh (#143) |
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
| 8 | `books.contentRevision` default 1, `chat_sessions`, `chat_turns` (#115). Tabel chat kosong saat upgrade; semua data lama dipertahankan |
| 9 | `chat_indexes` dan `chat_vectors` (#134), kosong saat upgrade; seluruh data user dipertahankan |
| 10 | `chat_turns.exploration` nullable JSON (#138); baris lama null, history dan index dipertahankan |

Tiap ubah tabel: naikkan `schemaVersion`, tambah langkah di `onUpgrade`, dan test migrasi dari versi sebelumnya (data tetap utuh, schema hasil migrasi sama dengan install baru). Restore backup dari schema lama ikut dimigrasi saat database dibuka ([backup.md](backup.md)).

## Pengaturan

API key di `flutter_secure_storage` (Keychain di iOS, Keystore di Android). Model ID, preferensi Aa, dan backup terakhir di tabel `settings` sederhana (key-value) di Drift, supaya ikut ter-backup. Model LLM: `ai.model` (model ID OpenRouter, default `z-ai/glm-5.3-flash`; pilihan dari daftar kandidat di [llm.md](llm.md)). API key di Keychain / Keystore dengan kunci `openrouter_api_key`, cuma disimpen setelah lolos cek bentuk dan cek ke OpenRouter ([llm.md](llm.md)); kosong = dihapus. "Hapus cache" di Pengaturan = kosongin `ai_results` + `ai_breakdowns` setelah konfirmasi; Pengaturan nampilin jumlah paragraf yang udah diterjemahin + ukuran teksnya. Backup terakhir: `backup.lastAt` (ISO 8601), `backup.lastName`, `backup.lastSize` (byte). Kunci Aa: `reader.size` (indeks step 0–6), `reader.font`, `reader.spacing`, `reader.margin`, `theme` (nama enum), `reader.hideStatusBar`, `reader.showProgressLine` (`true`/`false`). Urutan rak: `shelf.sort` (`lastOpened` / `title` / `added`, default `lastOpened`). Tampilan rak: `shelf.view` (`grid` / `list`, default `grid`). Hindari `shared_preferences` untuk data yang perlu ikut backup.


## Penyimpanan percakapan (#114/#115)

Schema **8** menambah penyimpanan mengikuti kontrak final
session/turn/quote/answer/source/index di `lib/domain/models/book_chat.dart`.
Repository/mapper (#116) tersedia; UI/transport belum dihubungkan ke aplikasi.
Session menyimpan judul/manualTitle, revision dan timestamps; `lastOpenedAt`
terpisah dari `updatedAt`. Turn memiliki sequence, attempt, model/promptVersion,
phase, draft, answer/error/status dan quote snapshot. Retry mengganti attempt pada
turn yang sama. Decoder tidak mempercayai JSON/enum backup: status turn tidak dikenal
menjadi interrupted; payload rusak diberi invalidResponse oleh mapper (#116).

SourceAnchor menyimpan book/revision + **chapter.id** + paragraphIndex + range
UTF-16 `[start,end)` + SHA-256 seluruh teks paragraf + snapshot teks range. Quote
multi-paragraf menggunakan beberapa anchor. Snapshot history tidak di-FK cascade
ke paragraf yang dapat diganti; book delete tetap menghapus sessions/turns. Semua
anchor wajib cocok lagi sebelum menjadi konteks baru atau tujuan navigasi.

Decoder arsip merekonstruksi snapshot tersimpan dengan validasi struktural/ownership,
tanpa mengharuskan paragraf lama masih ada. `parseChatAnswer` adalah validator output
live terhadap sumber attempt yang dikirim, bukan decoder arsip terhadap isi buku baru.
Arsip tetap terbaca, tetapi tidak boleh dipakai untuk prompt baru atau jump yang stale.

### `chat_sessions`

| Kolom | Tipe | Catatan |
|-------|------|---------|
| id | int PK autoincrement | Row Drift `ChatSessionRow`, berbeda dari model domain |
| bookId | int FK books.id cascade | Hapus buku menghapus sesi dan turn |
| contentRevision | int | Revision isi buku saat sesi dibuat; bookId/revision turn diwarisi dari sesi |
| title, manualTitle | text, bool default false | Judul otomatis atau hasil rename |
| createdAt, updatedAt | datetime default now | lastOpenedAt tidak ikut berubah saat jawaban ditulis |
| lastOpenedAt | datetime? | Index `chat_sessions_book_opened(book_id,last_opened_at,id)` |
| scrollAnchor | text? | JSON `{turnId,blockIndex,alignment}`; fraksi alignment, bukan pixel |

### `chat_turns`

| Kolom | Tipe | Catatan |
|-------|------|---------|
| id | int PK autoincrement | Row Drift `ChatTurnRow` |
| sessionId | int FK chat_sessions.id cascade | Tidak ada FK ke chapter/paragraf snapshot |
| sequence | int | Unique `(session_id,sequence)` juga menyediakan index urutan pesan |
| question | text | Pertanyaan asli |
| quote | text? | JSON ChatQuote: anchors + translation opsional (UI saja) |
| answer | text? | JSON jawaban tervalidasi: status + claims `{text,sourceIds}`; note diturunkan dari status, tidak mempercayai note model |
| sources | text default `[]` | JSON daftar sumber attempt: id/chapterTitle/anchors, termasuk snapshot asli |
| exploration | text? | Checkpoint penelusuran policy1; identitas turn/sesi/buku/revision/model, manifest, rencana/cursor/catatan atau pending query. Null pada history lama; bukan jawaban atau sumber asli |
| draft | text default kosong | Respons mentah/parsial, dipertahankan saat stop/cut/restart; tidak menjadi history terpercaya |
| phase | text | Nama ChatPhase; teks mentah agar enum rusak ditangani mapper, bukan textEnum yang melempar saat query |
| attempt | int default 1 | Generation retry pada turn yang sama |
| model, promptVersion | text, int | Identitas attempt |
| error, httpStatus | text?, int? | AiError.name dan status HTTP bila tersedia |
| createdAt, updatedAt | datetime default now | Tidak mengubah lastOpenedAt sesi |

JSON/enum bukan data terpercaya. Mapper #116 wajib memvalidasi struktur, ownership,
revision, angka dan range; payload rusak menjadi invalidResponse, phase tidak dikenal
menjadi interrupted. `answer` adalah hasil terstruktur, `draft` respons mentah; tidak
menyimpan salinan raw answer kedua. Semua sumber berada pada `sources`; claims mengacu
ke ID lokal attempt itu. Snapshot arsip didekode tanpa mensyaratkan paragraf lama ada.

Mapper `chat_snapshot.dart` memvalidasi JSON/enum, batas byte, angka, book/revision,
range UTF-16/snapshot length, hash SHA-256, urutan anchor, dan ID sumber/klaim.
Payload turn rusak menjadi failed/invalidResponse tanpa answer/quote terpercaya;
unknown phase tetap interrupted. Session rusak membawa flag domain `invalid`
dan tetap dapat dihapus; preview/invalid hanya hasil query, bukan kolom schema.
Live prepare/finalize memeriksa lagi paragraf/owner/hash terkini. Note model
tidak disimpan sebagai teks terpercaya; copy diturunkan dari status jawaban.

Archive tetap boleh dibuka, di-scroll dan dihapus, tetapi append/retry/rename atau
checkpoint ke revision lama ditolak. `markOpened` dan scroll tidak mengubah
updatedAt; terminal dan checkpoint yang benar-benar dipersist memperbarui aktivitas.

Migrasi hanya `ADD COLUMN` dan `CREATE TABLE/INDEX`; tidak mengganti tabel lama.
Backup ZIP tetap format 1 karena membawa snapshot seluruh DB; manifest melaporkan
schema 8. Downgrade binary schema 7 tidak didukung: rollback data memakai backup
sebelum upgrade, bukan menurunkan PRAGMA user_version atau menghapus app.


### Schema 11: hierarki bab (#143)

Satu kolom nullable `chapters.section`, migrasi `ADD COLUMN`, data lain utuh.
Judul bab dari TOC yang dimulai dengan heading-nya ("III: Of Providence" vs
heading "III") kini dipertahankan utuh; buku lama mendapat judul itu lewat
backfill. Anchor/paragraf tidak dinomori ulang; `parserVersion` tetap 1.

## Cache index Ngobrol (#134)

`chat_indexes`: id, bookId (FK cascade), identity unik (JSON versi format1,
bookId/contentRevision/parser/chunkPolicy/model/dimensions/queryTemplate), manifest,
chunkCount, ready defaultfalse. `chat_vectors`: indexId (FK cascade), ordinal,
vector BLOB Float32 little-endian, checksum SHA-256 base64 BLOB; PK(indexId,ordinal).
Anchor tidak disalin: chunk/anchor dibangun ulang dari teks dan dicek manifest-nya.
Index lengkap dan partial ikut backup sebagai data turunan yang bisa dibuat ulang.
Perubahan isi melalui contentChanged menghapus cache buku; hapus buku cascade.
Hapus sesi tidak menghapus cache. Index building menyimpan prefix batch sukses;
ready hanya setelah semua vektor tersimpan. Tidak ada transaksi selama network.

### Format jawaban chat v2 (#137)

Schema DB tetap9; kolom answer tetap JSON. Payload lama tanpa formatVersion memakai
claims/sourceIds dan batas2klaim. Payload baru memakai formatVersion2, status
answered/partial/clarify/off_topic, serta parts text/kind/sourceIds. Mapper membaca
keduanya tanpa menulis ulang data lama. Paragraf book memerlukan sumber; external
dan conversation tidak memakai sitasi buku, interpretation dapat merujuk gagasan
asal. Versi/jenis/ID tidak dikenal dan key duplikat ditolak. Finalize tetap mengecek
exact frozen sources untuk setiap referensi. Binary lama tidak dijanjikan membaca
format2; tidak ada downgrade data.

### Checkpoint penelusuran (#138)

Schema10 menambah satu kolom nullable, tanpa tabel/layanan baru. FK sesi/buku existing
menghapus checkpoint bersama turn. Payload diperiksa sebelum dipakai, terikat ke
ID turn dan question asli, model/policy/prompt dan manifest seluruh window; payload
rusak tidak memulai request atau menghapus jawaban lama. Lanjutkan menyalin progres
ke turn baru dan mengganti owner turnId secara atomik; finished answer/source lama
tidak ditulis ulang. Retry interrupted tetap satu turn; pergantian model/prompt
pada retry eksplisit memulai checkpoint baru. Jangan downgrade binary schema9;
gunakan backup sebelum upgrade sebagai rollback data.

Preview streaming (#141) tidak menambah kolom/schema: `ChatTurn.preview` dibaca
secara defensif dari `draft` saat snapshot, tanpa sumber. Preview runtime dengan
sumber provisional terikat attempt di ViewModel. Keduanya bukan `answer` dan
selalu dikecualikan dari trustedHistory. Invalid/corrupt draft berhenti di teks
terbaca terakhir tanpa mengubah paid answer lain.

### Checkpoint policy 2 (#143)

Checkpoint menambah `chapterIds` (bab yang dibaca; manifest = window bab itu),
`stopReason` (`budget | deadline | stagnant | complete`) dan strategi `chapters`.
Policy 1 lama tidak bisa dilanjutkan (`chatCanContinue` false, "kirim pertanyaan
baru"); jawaban/sumber turn lama tetap terbaca. Draft turn yang diperbaiki
otomatis memuat output lama diikuti output perbaikan; preview dari draft berhenti
di teks terbaca pertama.

### Schema 12: `chat_chapter_notes` (#151)

| Kolom | Tipe | Catatan |
|-------|------|---------|
| id | int PK | |
| bookId | int FK books cascade | Hapus buku ikut menghapus |
| contentRevision | int | Revision isi saat catatan dibuat |
| chapterId | int FK chapters cascade | Unique `(chapterId, policy)` |
| manifest | text | Hash window bab (`chatWindowManifest`); beda = bab dibaca ulang |
| policy | int | `chatChapterNotesPolicy` (format/isi catatan) |
| model | text | Model yang menulis catatan; cache tetap dipakai model lain |
| notes | text | JSON `[{text, anchors:[[paragraphIndex,start,end]]}]`, catatan generatif, bukan kutipan |
| createdAt | datetime | |

Data turunan: ikut backup (snapshot DB), dihapus `contentChanged`, tidak dihapus
saat sesi dihapus. Migrasi `CREATE TABLE`; baris rusak diabaikan saat dibaca.
