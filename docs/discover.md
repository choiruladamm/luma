# Cari & Download Buku (Discover)

Cari buku public domain dan download langsung ke rak, tanpa keluar app. Induk: [#163](https://github.com/choiruladamm/luma/issues/163). UI belum didesain (board Stabilo menyusul); file ini ngunci sisi teknisnya.

## Kenapa

Alur sekarang: Safari → gutenberg.org → download → file picker. Friksi nyari buku berikutnya bikin males mulai buku baru pas dogfooding. Cuma buku public domain yang bisa ditutup fitur ini; buku modern butuh lisensi penerbit.

## Hasil riset sumber (31 Okt 2026)

Diprobe langsung pakai curl, UA dengan kontak.

| Sumber | Hasil | Keputusan |
|---|---|---|
| Gutendex (`gutendex.com`) | Konek ke Cloudflare, origin ngegantung: 1 dari 13 request sukses, itu pun 20 detik. Docs-nya sendiri bilang instance publik bukan buat jangka panjang. | **Gugur.** |
| Gutenberg OPDS (`/ebooks/search.opds/`) | 200, 1–6 detik, `sort_order=downloads`, 25/halaman, link `next`. XML pensiun 2027, OPDS2 JSON masih diuji. | **Adapter pertama.** |
| Gutenberg `format=json` | Cuma OpenSearch suggestion (list judul). | Gak dipakai. |
| Dump `pg_catalog.csv.gz` | 5,6 MB gz / 21 MB raw, 79k baris, 62k teks Inggris. Judul, penulis (+ tahun hidup), subjek, bookshelves. Ditulis ulang mingguan, ada `Last-Modified`. Gak ada download_count. | Katalog lokal ([#169](https://github.com/choiruladamm/luma/issues/169)). |
| EPUB + cover gutenberg.org | 200. `.epub.noimages` ~0,5 MB; `.epub3.images` bisa 25 MB. | Pakai `.epub.noimages`. |
| Standard Ebooks | EPUB terbaik, tapi feed OPDS + bulk download cuma buat Patrons Circle (Basic auth email). Gratisnya scrape HTML. | Ditunda. |
| Internet Archive | Search gratis, tapi EPUB non-Gutenberg = OCR mentah, yang Gutenberg = duplikat. Download sering 503. | Skip. |
| Open Library | Gak punya EPUB, cuma metadata/cover → lempar ke IA. | Skip. |
| Feedbooks, ManyBooks | Mati 2024 / 403. | Skip. |

Gak ada aggregator gratis lintas sumber. OPDS satu-satunya protokol bersama, tapi dua dari tiga sumber yang layak gak cocok.

## Keputusan

- **Langsung dari HP, tanpa backend.** Satu user gak nyentuh batas gutenberg.org (~100 download/hari). Backend/self-host baru masuk akal kalau ada user lain atau kena rate limit.
- **Interface `BookSource` dari awal** (keputusan produk: multi-sumber), adapter per provider di `data/services/`. Registry `bookSourcesProvider` = `List<BookSource>`; nambah sumber = satu file adapter + satu baris.
- **Bahasa dikunci Inggris di adapter.** Gak ada filter di interface maupun setting.
- **Cari = katalog lokal, OPDS cuma populer / detail / download.** `search('')` → OPDS `sort_order=downloads`; `search('q')` → `CatalogRepository.search` (FTS5, instan, offline, [#169](https://github.com/choiruladamm/luma/issues/169)). Adapter Gutenberg yang ngeroute, UI cuma kenal `BookSource`.
- **Bytes EPUB langsung ke `importEpub`** yang udah ada (dedup sha256). `SourceType` tetep `epub`. Metadata rak (judul, penulis, cover) dari parser EPUB, bukan dari katalog.
- **Kolom baru `books.sourceId` + `books.externalId`** (migrasi + test) biar hasil cari bisa nunjukin "udah di rak" sebelum download.
- **Download di Notifier level app** (tanpa `autoDispose`): satu download jalan, sisanya antri; pindah layar gak batal; selesai = toast + masuk rak. Cuma app kill yang motong. Gak pakai `background_downloader`.
  - `downloadQueueProvider` (`ui/features/discover/view_models/download_queue_view_model.dart`, `Notifier<List<DownloadItem>>`): `enqueue(book)` (lagi antri / jalan = no-op, yang udah selesai diganti), `cancel(key)` (antri = hilang; jalan = berhenti di checkpoint berikutnya lalu hilang), `dismiss(key)` buat entri selesai / gagal. Status `queued → downloading(progress) → importing → done / duplicate / failed(error)`; `key` = `sourceId/externalId`. Import pakai `fileName` `pg{id}.epub`, bawa `sourceId` + `externalId`.
  - `DownloadToasts` di `builder` MaterialApp (di atas router): tiap entri yang baru selesai → toast "Sip, udah masuk rak!" / "Udah ada di rak" (· Baca, push lewat `routerProvider`) / "Gagal ngunduh". Copy final nyusul board (#167).
- **Cover hasil cari** pakai `cached_network_image` (dependensi baru). Cover rak tetep dari EPUB.
- **Cache halaman populer** in-memory per sesi di ViewModel, key `(sourceId, page)`. Hasil cari lokal gak di-cache (±6 ms).

Ditunda (ditambah pas kebutuhannya nyata): cache abstrak lintas sumber, filter generik (subjek, penulis), rating.

## Interface

```dart
abstract interface class BookSource {
  String get id;    // 'gutenberg', 'standard_ebooks', ...
  String get name;  // label UI

  /// query '' = daftar populer, selain itu hasil cari.
  /// Gutenberg: populer dari OPDS, cari dari katalog lokal.
  Future<CatalogPage> search(String query, {int page = 1});

  Future<CatalogBookDetail> fetchDetail(String externalId);

  Future<Uint8List> download(
    CatalogBook book, {
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  });
}
```

Model freezed di `domain/models/`:

- `CatalogPage`: `items`, `hasMore`, `total` (nullable: dari `searchCount` buat "7 hasil"; populer OPDS gak tau total).
- `CatalogBook`: `sourceId`, `externalId`, `title`, `authors` (`List<CatalogAuthor>` dari `domain/catalog/`, bawa tahun hidup), `coverUrl`, `downloadUrl`. `sourceId + externalId` = identitas lintas sumber. Gak ada `language`: semua sumber dikunci Inggris.
- `CatalogBookDetail`: `summary`, `subjects`, `bookshelves`, `fileSize`, `issued` (tanggal masuk Gutenberg, bukan tahun terbit asli), `wikipediaUrl`. Sinopsis ada di `content` OPDS per buku (bagian `Summary:`), gak semua buku punya. "N buku lain di katalog" bukan di sini: UI panggil `CatalogRepository.countByAuthor` langsung.

## Adapter Gutenberg (OPDS + katalog lokal)

- Populer (`search('')`): `GET /ebooks/search.opds/?sort_order=downloads&start_index=<n>`, 25/halaman, link `next` → `hasMore`, `total` null. Per entri cuma id, judul, penulis (`content`, bentuk tampil "Jane Austen"; `content` "N downloads" = tanpa penulis), thumbnail generik. Entri navigasi (Subjects, Authors, ...) dibuang. Tiap id dicocokin ke katalog lokal (`byId`) biar penulis + tahun hidup konsisten sama hasil cari; gak ketemu = pakai judul + nama dari feed.
- Cari (`search('q')`): `CatalogRepository.search` + `searchCount` → `CatalogRow` dipetain ke `CatalogBook` (URL dirakit dari id). Tanpa jaringan. Katalog belum sync = halaman kosong; yang nyuruh sync itu layar cari (lihat Katalog lokal).
- URL dirakit dari id (konvensi stabil bertahun-tahun), tanpa request per item:
  - cover: `https://www.gutenberg.org/cache/epub/{id}/pg{id}.cover.medium.jpg`
  - EPUB: `https://www.gutenberg.org/ebooks/{id}.epub.noimages` (302 ke `/cache/epub/`, `followRedirects` cukup)
- `fetchDetail`: `GET /ebooks/{id}.opds` → sinopsis (paragraf `Summary:` di `content`, kalimat "automatically generated summary" dibuang), link Wikipedia (paragraf `Note:`), subjek LCSH, bookshelves (link `related` `/ebooks/bookshelf/`, judul "In X…" → "X"), ukuran file (`length` di link `.epub.noimages`), `issued` (`published`). **Gak ada**: download count, tahun hidup penulis (udah ada di `CatalogAuthor`).
- Parser XML `domain/catalog/opds_parser.dart` (`parseOpdsFeed`, `parseOpdsBook`) pakai package `xml`, pure, fixture asli di `test/fixtures/catalog/opds_*.xml`.
- Download: `dio.get` bytes ke `downloadUrl`, `receiveTimeout` 60 s per request, progres 0–1 (−1 tanpa `Content-Length`); `isCancelled` dicek tiap chunk → `CancelToken` → `DioException` tipe `cancel` (sama kayak sync katalog).
- HTTP bersama `data/services/http_client.dart`: `lumaUserAgent`, `lumaDio({receiveTimeout})` (connect 15 s), `retryOnBusy` (3× cuma 429/503, jeda 2 s × n). Dipakai `CatalogSyncService` dan `GutenbergSource`.
- Registry: `bookSourcesProvider` = `[GutenbergSource(catalogRepository)]`.

## Katalog lokal ([#169](https://github.com/choiruladamm/luma/issues/169))

Service mandiri buat ngolah `pg_catalog.csv.gz`, gak tergantung `BookSource` atau layar cari. Dump: 5,6 MB gz / 21 MB raw, 79k baris → 61.900 teks Inggris, parse ±0,6 detik di isolate.

**Parser** `domain/catalog/pg_catalog_parser.dart`: pure, CSV → `CatalogRow` (freezed: `id`, `title`, `authors[]`, `subjects[]`, `bookshelves[]`, `issued`). Parser CSV RFC 4180 ditulis sendiri (quote, `""`, koma + newline di dalam quote). Filter `Type=Text` dan `Language=en`; baris rusak (kolom kurang, id bukan angka) dilewatin. `Authors` dipecah `;`, tag peran `[Illustrator]` / `[Translator]` dibuang tapi orangnya tetep ikut; tahun = bagian terakhir setelah koma yang bentuknya `1775-1817` / `1900-` / `-1468` (`?` diabaikan), selain itu nama utuh tanpa tahun. `Bookshelves` ikut apa adanya termasuk entri `Category: …`.

**Tabel `catalog_books`** (schema v14, [data-model.md](data-model.md)): `id` = Text#, `title`, `authorsText` (nama dipisah `; `, buat tampil + index FTS), `authorsJson`, `subjectsJson`, `bookshelvesJson`, `issued` nullable. Index `title` + `authorsText`. **`catalog_fts`** (schema v15): virtual table FTS5 external-content di atas `catalog_books` (`title`, `authors_text`, tokenizer `unicode61 remove_diacritics 2`), ±4,3 MB buat 62k baris. Drift gak bisa deklarasiin virtual table, jadi dibuat lewat `customStatement` di `onCreate` / `onUpgrade` dan di-`rebuild` di akhir `replaceAll` (satu transaksi, 62k baris ±0,7 detik termasuk insert). Bukan data user: gak ikut backup, diganti utuh tiap sync. Meta di `settings`: `catalog.lastModified` (header `Last-Modified` dump, dikirim balik sebagai `If-Modified-Since`), `catalog.syncedAt` (ISO 8601), `catalog.count`.

**`CatalogRepository`** (`catalogRepositoryProvider`): `replaceAll` satu transaksi, batch per 2.000 baris (gagal = tabel lama utuh); `byId(id)`; `search(query, {page})` + `searchCount(query)` lewat FTS5: tiap kata input jadi prefix (`"jane"* "au"*`, AND implisit, `domain/catalog/catalog_query.dart`), kata dipecah di non-huruf/angka jadi kutip, `*`, `-`, `OR`, `NEAR` dari user gak pernah jadi sintaks MATCH; urut `bm25(catalog_fts, 10.0, 1.0)` (judul 10× penulis), seri → judul; 25/halaman; `pride prej` → Pride and Prejudice posisi 1 dalam ±6 ms; query tanpa kata = kosong; `byAuthor(name)` + `countByAuthor(name)` (buat "N buku lain") dan `byBookshelf(name)` cocokin token JSON persis (`"name":"Austen, Jane"`, `"Harvard Classics"`) di kolom JSON, tanpa tabel pivot; `bookshelves()` pakai `json_each` (distinct + jumlah); `stats()` / `watchStats()` dari `settings`; `isSynced` = count > 0. `catalogStatsProvider` = stream stats buat UI.

**`CatalogSyncService`** (`catalogSyncServiceProvider`): `sync({force})` → `skipped` (count > 0 dan `syncedAt` < 7 hari, tanpa `force`) / `notModified` (304, cuma `syncedAt` maju) / `updated`. Dio: UA `Luma/<versi> (+mailto:…)`, connect 15 s, receive 120 s, retry 3× cuma 429/503 (jeda 2 s × n). `If-Modified-Since` cuma dikirim kalau tabel udah ada isinya. 200 → `dio.download` streaming ke folder temp (progress 0–1; −1 kalau gak ada `Content-Length`), gunzip (`archive`) + parse di `Isolate.run`, `replaceAll`, simpen meta, hapus temp. Katalog kosong = `FormatException`. Gagal apa pun = tabel lama tetep.

**`catalogSyncProvider`** (`Notifier<CatalogSyncState>`, tanpa autoDispose, di file service): `idle` / `checking` / `downloading(progress)` / `importing` / `upToDate` (304, toast sekali lalu `dismiss()`) / `failed(reason)`. Satu sync jalan, `sync()` lagi = no-op; `cancel()` cuma pas `downloading` (`CancelToken` → balik `idle`). Teks tanggal + jumlah di idle dari `catalogStatsProvider`, bukan dari state.

**Pengaturan**, bagian "Katalog buku", baris `Katalog Gutenberg` pola `_CacheRow`: belum pernah → "Belum diunduh · 5,6 MB" + Unduh; idle → "Diperbarui 25 Okt 2026 · 61.900 buku" + Perbarui; checking / importing → spinner ("Ngecek versi terbaru…" / "Nyusun katalog…"); downloading → "Ngunduh 43%" + Batal; failed → "Gagal, katalog lama tetep dipakai" + Coba lagi; 304 → toast "Katalognya udah yang terbaru". Tombol selalu `force: true`. Sync pertama dari layar cari ("Nyiapin katalog…") dan sync otomatis > 7 hari dipasang pas layar cari ada, cuma manggil `sync()`.

Gak dibikin sampai ada bukti perlu: diff per baris, toleransi typo (tokenizer `trigram`, index 3×), sinonim, bobot popularitas (gak ada download count di CSV), sinopsis, notifikasi.

## Kebijakan jaringan

Aturan gutenberg.org ([robot_access](https://www.gutenberg.org/policy/robot_access.html)): traffic tanpa kontak diblok IP.

- User-Agent: `Luma/<versi> (+mailto:work.adamm@gmail.com)`, juga buat request cover.
- Timeout 15 detik search / 60 detik download.
- Retry 3× cuma buat 429/503, backoff bertahap. Error lain langsung ditampilin.
- Request cuma buat yang user lihat: gak prefetch halaman berikutnya, gak fetch detail per item di list.

## Test

- `test/domain/`: parser feed populer + per buku (fixture XML), rakit URL dari id, `CatalogRow` → `CatalogBook`.
- `test/data/`: adapter dengan Dio fake (paging populer, retry 429/503, timeout) + `CatalogRepository` in-memory buat `search('q')`, download → `importEpub` pakai EPUB kecil, migrasi kolom `sourceId`/`externalId`.
- `test/data/download_queue_test.dart`: antrian dengan sumber palsu (urutan, dobel, batal antri / jalan, gagal jaringan, EPUB rusak), download → import EPUB kecil masuk DB in-memory.
- `test/ui/features/discover/`: widget test layar cari, `bookSourcesProvider`, download notifier, `catalogSyncProvider`, `catalogStatsProvider` di-override pakai data palsu. `download_toasts_test.dart`: toast cuma pas status berubah jadi selesai.

## Board (page "09 · Cari buku")

17 layar terang + gelap, komponen NavBar, catatan alur di board "Draft · Cari & download buku · alur lengkap (arah A)". Urutan UI: [#172](https://github.com/choiruladamm/luma/issues/172) NavBar + shell routing → [#167](https://github.com/choiruladamm/luma/issues/167) tab Cari buku (03–09) → [#173](https://github.com/choiruladamm/luma/issues/173) detail buku (10–13) → [#174](https://github.com/choiruladamm/luma/issues/174) sheet Unduhan, toast, label Baru, rak kosong (01, 02, 14–17).

Keputusan implementasi yang gak ada di board:

- Katalog pertama kali belum ada: layout layar 07 dengan copy "Nyiapin katalog buku… 43%" dari `catalogSyncProvider`; gagal = layar 08.
- Tab Cari buku = `DiscoverView` + `discoverProvider` (`ui/features/discover/`): `PopularState` (loading / slow setelah 5 detik / ready Top 10 / failed offline · dead), `SearchResults` (query, items, total, hasMore, loadingMore, moreFailed) dari `search(q)` tiap ketikan tanpa debounce; `loadMore` pas sisa scroll < 200. Badge baris dari `shelfExternalIdsProvider` (stream `BookRepository.watchExternalIds`) + `downloadQueueProvider`. Cover jaringan lewat `CatalogCover` (muted pas belum kemuat, cover default kalau gagal). Kolom cari dimatiin sampai katalog ada.
- Fixture evaluasi Ngobrolin buku ngunci hash `pubspec.lock`; nambah dependensi UI (`cached_network_image`) = perbarui hash di manifest aktif (heldout v1, validation2, validation3) dan `pubspec.lock` masuk daftar `mutable` di `chat_retrieval_test`. Arsip `spike113` dan `refined_protocol_v2` gak disentuh.
- Offline (09) dideteksi dari error jaringan (`connectionError` / `SocketException`), dicoba lagi tiap tab dibuka; tanpa `connectivity_plus`.
- "Lagi rame" di-cache in-memory per sesi; buka app baru = request lagi.
- Kutipan layar 02 / 17 dari daftar kurasi hardcode (Pride and Prejudice, Emma, Alice); buku lain pakai kutipan Pride and Prejudice.
- Penulis di detail (tap) = balik ke cari dengan query nama penulis (FTS), bukan `byAuthor` persis.
- "App di latar: notifikasi lokal" (layar 15) ditunda ke [#175](https://github.com/choiruladamm/luma/issues/175): butuh dependensi + izin, iOS cuma ngasih ±30 detik di latar.

## Ditunda

- **Standard Ebooks** ([#168](https://github.com/choiruladamm/luma/issues/168)): adapter OPDS + Basic auth, kredensial di `flutter_secure_storage`. Dibuka kalau ikut Patrons Circle.
- **Backend aggregator** ([#168](https://github.com/choiruladamm/luma/issues/168)): dibuka kalau ada user lain atau kena rate limit.
- **Notifikasi lokal** ([#175](https://github.com/choiruladamm/luma/issues/175)): dibuka kalau #174 udah dipakai dan download kelar di latar pernah kelewat.
