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
- **Buku lama (sebelum v17):** migrasi cuma bikin tabel + trigger, gak ngisi. `BookSearchIndex.isIndexed(bookId)` ngecek ada-gak paragraf buku itu yang belum ada di `paragraph_fts_docsize`; `ensureIndexed(bookId, onProgress:)` ngisi per bab (idempoten, bisa dilanjut kalau kepotong) dan dipanggil pas sheet Cari kata kebuka (`_start` di `BookSearchViewModel`, layar "Nyiapin pencarian").
- **Restore backup:** index nempel ke rowid `paragraphs`, dan `VACUUM INTO` (backup) boleh nggeser rowid. `RestoreService.inspect` manggil `rebuildBookSearchIndex()` di salinan sementara sebelum dipasang, jadi hasil restore selalu konsisten, termasuk backup dari schema lama.
- **Re-import / `parserVersion` naik:** paragraf diganti, trigger yang ngurus indexnya.

## Query & repository (#178)

- **`domain/book_search.dart`** (murni): `BookSearchQuery.parse(input)` → null kalau < 2 huruf/angka. Kata dipecah di non-huruf/angka dan dilipat (huruf kecil, tanpa aksen), semua kata jadi **satu frasa**, kata terakhir prefix: `netherfield par` → `MATCH '"netherfield par"*'`. Teks user gak pernah jadi sintaks FTS5 (`"`, `*`, `-`, `OR`, `NEAR` ikut dibuang). `ranges(text)` nyari kata yang sama di teks asli (kata utuh, kata terakhir boleh lanjut ke ujung kata) buat cuplikan sekarang dan stabilo inline di reader (#180). `bookSearchSnippet` motong ±60 huruf kiri-kanan dengan "…".
- **`BookSearchRepository`** (`bookSearchRepositoryProvider`): `search(bookId, query)` join `paragraph_fts` → `paragraphs` → `chapters` (filter `book_id`), urut `chapters.sort_order` lalu `paragraph_index`, `LIMIT 501`. Hasil `BookSearchResult`: `chapters` (grup per bab, tiap hit bawa `chapterId`, `paragraphIndex`, `groupIndex`, `snippet`, `matchStart/End` di cuplikan), `total` + `chapterCount` sebenarnya (kalau > 500, dihitung lewat query `COUNT` terpisah), `truncated`.
- **Riwayat:** `recentSearches` / `saveRecent` / `clearRecents`, JSON list di `settings` key `search.recent.<bookId>` (ikut backup), terbaru dulu, dedupe abaikan besar/kecil, maks 5, query < 2 huruf gak disimpan, nilai rusak dibaca kosong. Hapus buku (`BookRepository.delete`) ikut ngebuang key-nya.

## Menu ⋯ + sheet (#179)

- **Kapsul atas:** `‹ · judul · Daftar isi · ⋯`. Tombol Aa dicopot; ⋯ (`CircleButton`, label "Aksi lain") kuning selama menu atau sheet dari menu (Aa) kebuka. Popover `showReaderMenu` (`reader_menu.dart`): 232 lebar, radius 20, garis kapsul 1,5, baris 50, rata kanan 10pt di bawah kapsul; isi **Cari kata** (ikon Search01) dan **Atur tampilan** (Aa + "Ukuran, font, tema"). Layar diredupin `scrimSoft`. "Tandain posisi nanti" di board cuma contoh isian UI, gak dibangun.
- **Sheet** `showBookSearchSheet` (`book_search_sheet.dart`): `showAppSheet` detent penuh, top 54 (`Layout.searchSheetTop`), isi di-padding `viewInsets.bottom` jadi daftar mengecil di atas keyboard. Kolom cari `SearchField` fokus otomatis + "Batal".
- **`BookSearchViewModel`** (`bookSearchProvider(bookId)`, `.autoDispose`): fase `checking` (tanpa tampilan) → `preparing` (buku belum ke-index: `ensureIndexed`, progres per bab, layar 5 "Nyiapin pencarian…" + "Bab N dari M") → `idle` (riwayat, layar 1) → `results` / `empty` (layar 2–4) / `failed`. Query berubah → cari 250 ms abis ketikan terakhir (`BookSearchViewModel.debounce`); kurang dari 2 huruf balik ke riwayat; jawaban lama yang telat gak nimpa yang baru (`_seq`). Tap riwayat = cari langsung. Query yang diketik pas `preparing` dicari begitu index siap.
- **Tap hasil:** `remember()` nyimpen query ke riwayat, sheet nutup balikin `BookSearchPick` (query, hasil lengkap, hit). Lompat + navigator: bagian berikutnya (#180).
- **Komponen shared** (`ui/core/widgets/`): `SearchField` (pill 44, diam muted, fokus garis tinta 1,5 + cincin kuning 4, × 22 pas ada isi), `SearchGroupHeader` (judul bab + chip `Tag.status('Lagi dibaca')` + "N hasil"), `SearchHitTile` (cuplikan maks 3 baris, kata cocok di-stabilo inline, `Radii.xs`). Ikon baru di `AppIcons`: `search`, `searchOff`, `up01`, `down01`.

## Lompat, navigator, keluar (#180)

Mode cari hidup di `_ReaderViewState` (`reader_view.dart`): `SearchMode` (`reader_types.dart`; kata, daftar hasil urut baca + judul bab tiap hasil, hasil yang lagi dibuka, posisi baca sebelum nyari). Nyala pas hasil di-tap di sheet, mati lewat × di navigator.

- **Lompat** (`_jumpToHit`): bab yang sama → `ChapterTextState.jumpToParagraph` (`_place` ke ⅓ tinggi layar, instan, kedip); bab lain → ganti bab lewat jalur `restoreTo` yang sama kayak "Lanjut baca", tapi dateng-lewat-cari (`flashSearch`) gak manggil `_greet` (gak ada intro kapsul). Kedip = mekanisme `_mark`/`_flash` "Lanjut baca" dengan durasi `Motion.searchFlash` (600 ms); Kurangi gerakan: garis kiri 4pt.
- **Stabilo inline:** `_paragraphText` ngubah kata cocok (`BookSearchQuery.ranges`, domain murni yang sama dipakai buat cuplikan sheet) jadi `TextSpan` dengan `backgroundColor`. Kata yang lagi dibuka (cocok pertama di paragraf hasil): `highlight` penuh + garis bawah 1,5; kata cocok lain yang keliatan: `highlight` alpha 0,5. Pengecualian aturan highlight (`highlight` aslinya cuma buat grup yang dibuka di Artinya): `docs/design.md`.
- **Posisi baca ditahan:** `_jumpToHit` ngeset `_jumpHeld`. `_save()` tanpa `force` tetap nyatet waktu baca tapi gak nulis `reading_progress` selagi ditahan; `_goTo` (daftar isi) dan `_returnTo` ngelepas. `ChapterTextState` nyimpen posisi scroll waktu lompat (`_searchAnchor`); begitu scroll jari berhenti dan jaraknya ≥ 1 layar dari situ → `onSearchRead` → `_jumpHeld = false` + simpan. Keluar reader sebelum itu = posisi lama utuh. Potongan waktu baca juga diputus di lompatan (`_flushReading` sebelum pindah, `_lastChar` di-reset), jadi lompatan gak kehitung karakter terbaca.
- **Navigator** (`ui/core/widgets/search_navigator.dart`): gantiin `ReaderChatDock` (pill progres + tombol Ngobrol) selama mode cari, di posisi yang sama, gak ikut ngumpet bareng kapsul. Penuh: pill 50, `↑` · kata + "1 dari 68 · Chapter I" · `↓` | `×`; target tap 44 (lingkaran 36). `↑`/`↓` redup di ujung daftar, pindah hasil lintas bab. Tap tengah = buka lagi sheet dengan kata dan posisi scroll daftar yang sama (`initialQuery`, `initialScrollOffset`). Pas jari scroll: ngecil (pill 46, "1/68", tanpa kata, `AnimatedSize` 150 ms); balik penuh `Motion.searchRegrow` (1,2 dtk) abis scroll berhenti; lompat = langsung penuh. Lebih dari 500 hasil: "dari 500+".
- **Kapsul:** ⋯ dapet titik kuning (`ReaderTopCapsule.searchActive`); item pertama menu ⋯ jadi "Lihat hasil “kata”" (`ReaderMenuAction.results`), Atur tampilan tetap.
- **Keluar (×):** `_search = null`, stabilo hilang, pill progres balik, toast "Balik ke posisi tadi?" + tombol "Balik" 6 detik (`Motion.searchToast`). "Balik" = `_returnTo`: bab + titik sebelum nyari lewat jalur restore ("Lanjut baca"), lanjut baca biasa dari situ. Posisi sebelum nyari dicatat sekali, bukan tiap ganti kata.

## Performa & edge case (#181)

- **Performa** (`test/data/book_search_perf_test.dart`, buku sintetis 150 bab × 100 paragraf = 15 000 paragraf): cari kata langka ≈ 9 ms, kata umum ("the", 12 542 hasil, kepotong 500 + `COUNT`) ≈ 14 ms, frasa ≈ 10 ms; backfill seluruh buku ≈ 35 ms. Batas test sengaja longgar (250 / 1000 / 500 ms) biar gak flaky di CI. Backfill ngasih giliran ke UI tiap bab (callback progres, 151 langkah) dan aman dijalanin dua kali barengan (`NOT EXISTS` di `paragraph_fts_docsize`, statement Drift ke-serial): gak ada baris dobel.
- **Buku Markdown** dan **buku 1 bab**: sama persis jalurnya (trigger di `paragraphs`, bab tanpa hasil gak muncul di daftar).
- **Hasil di paragraf yang gak digambar** (heading pertama yang sama kayak judul bab dibuang `_withoutTitleHeading`): `jumpToParagraph` gak nemu kotaknya → mendarat di awal bab, gak error. Navigator dan stabilo tetap jalan.
- **Teks besar (Dynamic Type):** sheet ngalir (daftar scroll, baris tumbuh); navigator nge-clamp skala teks ke 1,2 karena tinggi pill tetap (kayak kapsul baca). **Landscape + keyboard:** sheet di-padding `viewInsets.bottom`, isi mengecil di atas keyboard.
- **Sheet ditutup pas lagi nyiapin index:** `ensureIndexed` jalan terus (gak dibatalin); buka lagi = lanjut dari bab yang belum.
- **Cache stabilo:** `BookSearchQuery.ranges` dihitung ulang per paragraf tiap `build` bab. Bab ≈ 100 KB masih murah; kalau ada bab raksasa yang kerasa berat, simpan hasilnya per (kata, paragraf).

## Test

- `test/data/book_search_index_test.dart`: trigger, aksen/kutip, update/hapus/cascade, backfill per buku + progres, hapus baris belum ke-index gak ngerusak index, rebuild abis rowid geser.
- `test/data/migration_test.dart`: v16 → v17 (data utuh, backfill, schema sama install baru).
- `test/domain/book_search_test.dart`: parse, injeksi, lipat aksen/kutip, `ranges`, cuplikan.
- `test/data/book_search_repository_test.dart`: urutan per bab, lingkup buku, frasa, cap 500, riwayat, hapus buku.
- `test/ui/features/reader/book_search_view_model_test.dart` (fakeAsync): debounce, fase, urutan jawaban, riwayat. `book_search_sheet_test.dart`: layar 1–5, chip, stabilo, tap hasil, Batal, keyboard. `reader_test.dart` grup "menu ⋯": kapsul, menu, buka sheet. `test/ui/core/search_field_test.dart`, `search_result_test.dart`.
- `test/ui/features/reader/reader_test.dart` grup "Cari kata di reader": navigator gantiin dock + titik di ⋯, stabilo penuh/setengah, posisi ditahan sampai scroll 1 layar, ↑ ↓ lintas bab, × + "Balik", tap tengah buka sheet lagi + "Lihat hasil", ngecil pas scroll. `test/ui/core/search_navigator_test.dart`.
- `test/data/book_search_perf_test.dart`: kecepatan cari + backfill di 15 000 paragraf, backfill ganda.
- `test/data/import_*_test.dart`, `restore_service_test.dart`: index ikut import dan restore.
