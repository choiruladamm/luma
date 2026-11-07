# Cari kata

Cari kata atau kalimat di buku yang lagi dibaca, tap hasil, langsung lompat ke paragrafnya. Induk: [#176](https://github.com/choiruladamm/luma/issues/176). Desain: board "10 · Cari kata" di Stabilo. Namanya "Cari kata" biar gak ketuker sama tab "Cari buku" ([discover.md](discover.md)).

## Keputusan

- **Titik masuk:** menu ⋯ di kapsul atas (Cari kata, Atur tampilan; Aa pindah ke sini). Cari gak punya tombol sendiri; kapsul maks 2 tombol aksi. "Tandain posisi nanti" di board cuma contoh isian UI, gak dibangun.
- **Lingkup:** selalu semua bab. Yang dicari teks asli buku (Inggris); terjemahan cache gak ikut.
- **Pencocokan:** mulai 2 huruf, jeda 250 ms abis berhenti ngetik. Gak peduli huruf besar/kecil, aksen (`café` = `cafe`), dan kutip lurus vs miring (`’` = `'`).
- **Hasil:** per bab sesuai urutan buku, di dalam bab sesuai urutan paragraf. Cuplikan ±60 huruf kiri-kanan, maks 3 baris. "68 hasil di 31 bab"; lebih dari 500 → 500 pertama + "Kebanyakan, coba kata yang lebih spesifik".
- **Riwayat:** maks 5 per buku, disimpan pas tap hasil (bukan tiap ketikan).
- **Lompat:** posisi baca gak ikut pindah; baru ke-update kalau lanjut baca (scroll 1 layar).

## Index (#177)

Tabel `paragraph_fts` (schema 17): FTS5 external-content di atas `paragraphs` (teks gak dobel), `tokenize='unicode61 remove_diacritics 2'`, satu kolom `text`. Bukan tabel Drift; dibuat lewat `AppDatabase.createBookSearchFts` (onCreate + onUpgrade).

- **Trigger di `paragraphs`** (`paragraph_fts_ai/_ad/_au`) yang ngejaga isinya. Import EPUB, import Markdown, dan ganti bab (hapus + insert) otomatis ke-index, satu transaksi sama datanya; cascade hapus buku ikut bersih. Heading ikut di-index, `sceneBreak` nggak.
- **Hapus/ubah baris yang belum ke-index** (buku lama) bakal ngerusak index FTS5 kalau trigger ngirim `'delete'` buta. Trigger cuma ngirim kalau rowid-nya ada di `paragraph_fts_docsize`.
- **Kutip miring:** `’` dan `'` sama-sama pemisah token di unicode61, jadi `don’t` dan `don't` ketemu satu sama lain tanpa normalisasi teks.
- **Buku lama (sebelum v17):** migrasi cuma bikin tabel + trigger, gak ngisi. `BookSearchIndex.isIndexed(bookId)` ngecek ada-gak paragraf buku itu yang belum ada di `paragraph_fts_docsize`; `ensureIndexed(bookId, onProgress:)` ngisi per bab (idempoten, bisa dilanjut kalau kepotong) dan dipanggil pas pertama kali cari (layar "Nyiapin pencarian").
- **Restore backup:** index nempel ke rowid `paragraphs`, dan `VACUUM INTO` (backup) boleh nggeser rowid. `RestoreService.inspect` manggil `rebuildBookSearchIndex()` di salinan sementara sebelum dipasang, jadi hasil restore selalu konsisten, termasuk backup dari schema lama.
- **Re-import / `parserVersion` naik:** paragraf diganti, trigger yang ngurus indexnya.

## Query & repository (#178)

- **`domain/book_search.dart`** (murni): `BookSearchQuery.parse(input)` → null kalau < 2 huruf/angka. Kata dipecah di non-huruf/angka dan dilipat (huruf kecil, tanpa aksen), semua kata jadi **satu frasa**, kata terakhir prefix: `netherfield par` → `MATCH '"netherfield par"*'`. Teks user gak pernah jadi sintaks FTS5 (`"`, `*`, `-`, `OR`, `NEAR` ikut dibuang). `ranges(text)` nyari kata yang sama di teks asli (kata utuh, kata terakhir boleh lanjut ke ujung kata) buat cuplikan sekarang dan stabilo inline di reader (#180). `bookSearchSnippet` motong ±60 huruf kiri-kanan dengan "…".
- **`BookSearchRepository`** (`bookSearchRepositoryProvider`): `search(bookId, query)` join `paragraph_fts` → `paragraphs` → `chapters` (filter `book_id`), urut `chapters.sort_order` lalu `paragraph_index`, `LIMIT 501`. Hasil `BookSearchResult`: `chapters` (grup per bab, tiap hit bawa `chapterId`, `paragraphIndex`, `groupIndex`, `snippet`, `matchStart/End` di cuplikan), `total` + `chapterCount` sebenarnya (kalau > 500, dihitung lewat query `COUNT` terpisah), `truncated`.
- **Riwayat:** `recentSearches` / `saveRecent` / `clearRecents`, JSON list di `settings` key `search.recent.<bookId>` (ikut backup), terbaru dulu, dedupe abaikan besar/kecil, maks 5, query < 2 huruf gak disimpan, nilai rusak dibaca kosong. Hapus buku (`BookRepository.delete`) ikut ngebuang key-nya.

## Test

- `test/data/book_search_index_test.dart`: trigger, aksen/kutip, update/hapus/cascade, backfill per buku + progres, hapus baris belum ke-index gak ngerusak index, rebuild abis rowid geser.
- `test/data/migration_test.dart`: v16 → v17 (data utuh, backfill, schema sama install baru).
- `test/domain/book_search_test.dart`: parse, injeksi, lipat aksen/kutip, `ranges`, cuplikan.
- `test/data/book_search_repository_test.dart`: urutan per bab, lingkup buku, frasa, cap 500, riwayat, hapus buku.
- `test/data/import_*_test.dart`, `restore_service_test.dart`: index ikut import dan restore.
