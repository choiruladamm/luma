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
- **Bytes EPUB langsung ke `importEpub`** yang udah ada (dedup sha256). `SourceType` tetep `epub`. Metadata rak (judul, penulis, cover) dari parser EPUB, bukan dari katalog.
- **Kolom baru `books.sourceId` + `books.externalId`** (migrasi + test) biar hasil cari bisa nunjukin "udah di rak" sebelum download.
- **Download di Notifier level app** (tanpa `autoDispose`): satu download jalan, sisanya antri; pindah layar gak batal; selesai = toast + masuk rak. Cuma app kill yang motong. Gak pakai `background_downloader`.
- **Cover hasil cari** pakai `cached_network_image` (dependensi baru). Cover rak tetep dari EPUB.
- **Cache hasil search** in-memory per sesi di ViewModel, key `(sourceId, query, page)`.

Ditunda (ditambah pas kebutuhannya nyata): cache abstrak lintas sumber, filter generik (subjek, penulis), rating.

## Interface

```dart
abstract interface class BookSource {
  String get id;    // 'gutenberg', 'standard_ebooks', ...
  String get name;  // label UI

  /// query '' = daftar populer (atau apa pun yang sumbernya bisa).
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

- `CatalogPage`: `items`, `hasMore`.
- `CatalogBook`: `sourceId`, `externalId`, `title`, `authors`, `coverUrl`, `downloadUrl`, `language`. `sourceId + externalId` = identitas lintas sumber.
- `CatalogBookDetail`: `summary`, `subjects`, `bookshelves`, `fileSize`, `published`, `wikipediaUrl`. Sinopsis ada di `content` OPDS per buku (bagian `Summary:`), gak semua buku punya.

## Adapter Gutenberg (OPDS)

- Search: `GET /ebooks/search.opds/?query=<q>&sort_order=downloads&start_index=<n>`. Query kosong = populer. Feed search per entri cuma id, judul, penulis (`content`), thumbnail generik. Entri navigasi (Subjects, Authors, ...) dibuang.
- URL dirakit dari id (konvensi stabil bertahun-tahun), tanpa request per item:
  - cover: `https://www.gutenberg.org/cache/epub/{id}/pg{id}.cover.medium.jpg`
  - EPUB: `https://www.gutenberg.org/ebooks/{id}.epub.noimages` (302 ke `/cache/epub/`, `followRedirects` cukup)
- `fetchDetail`: `GET /ebooks/{id}.opds` → sinopsis (`Summary:` di `content`), link Wikipedia, subjek LCSH, bookshelves, ukuran file (`length` di link EPUB), tahun terbit. Bisa koreksi URL kalau beda dari rakitan. **Gak ada**: download count, tahun hidup penulis (dari katalog lokal).
- Search dan "buku lain penulis ini" pindah ke katalog lokal begitu #169 masuk; OPDS tinggal buat populer, detail, download.
- Parser XML pakai package `xml` yang udah ada, pure, dites pakai fixture.

## Katalog lokal ([#169](https://github.com/choiruladamm/luma/issues/169))

Service mandiri buat ngolah `pg_catalog.csv.gz`, gak tergantung `BookSource` atau layar cari.

- `domain/catalog/pg_catalog_parser.dart`: pure, CSV → `CatalogRow` (id, judul, penulis + tahun hidup, subjek, bookshelves, tahun). Filter `Type=Text`, `Language=en`. Parser CSV ditulis sendiri.
- Tabel `catalog_books` (schema v14), index `title` + `authorsText`. Meta di `settings`: `catalog.lastModified`, `catalog.syncedAt`, `catalog.count`.
- `CatalogRepository`: `replaceAll` dalam satu transaksi (gagal = tabel lama utuh), `search` LIKE judul/penulis 25/halaman, `byAuthor`, `byBookshelf`, `bookshelves`, `stats`.
- `CatalogSyncService` + `catalogSyncProvider`: `sync({force})`. Otomatis kalau > 7 hari (dipanggil layar cari nanti), manual lewat tombol Perbarui di Pengaturan. `If-Modified-Since` → `304` = cuma update `syncedAt`; `200` = download streaming (progress, bisa batal) → gunzip + parse di isolate → `replaceAll`. State: idle / checking / downloading / importing / failed. Satu sync jalan, sisanya no-op.
- Sync pertama ngeblok layar cari ("Nyiapin katalog…"), berikutnya diam-diam. Gagal = katalog lama tetep dipakai.
- Gak dibikin: diff per baris, FTS5 (LIKE di 62k baris < 50 ms), sinopsis/download count (gak ada di CSV).

## Kebijakan jaringan

Aturan gutenberg.org ([robot_access](https://www.gutenberg.org/policy/robot_access.html)): traffic tanpa kontak diblok IP.

- User-Agent: `Luma/<versi> (+mailto:work.adamm@gmail.com)`, juga buat request cover.
- Timeout 15 detik search / 60 detik download.
- Retry 3× cuma buat 429/503, backoff bertahap. Error lain langsung ditampilin.
- Request cuma buat yang user lihat: gak prefetch halaman berikutnya, gak fetch detail per item di list.

## Test

- `test/domain/`: parser feed search + per buku (fixture XML), rakit URL dari id.
- `test/data/`: adapter dengan Dio fake (paging, retry 429/503, timeout), download → `importEpub` pakai EPUB kecil, migrasi kolom `sourceId`/`externalId`.
- `test/ui/features/discover/`: widget test layar cari, `bookSourcesProvider` + download notifier di-override pakai sumber palsu.

## Catatan buat board (draft arah A, page 90 Drafting)

Draft 17 layar udah nutup alur utama. Yang perlu disesuaikan sebelum #167 dibuka:

- Versi gelap belum ada.
- "Diunduh 9.400 kali bulan ini" dan "#1 minggu ini": Gutenberg cuma ngasih urutan populer, gak ada angka dan gak per minggu. Buang angkanya, copy jadi "Lagi rame".
- Tahun hidup penulis dan "N buku lain": dari katalog lokal (#169), bukan OPDS.
- Sinopsis: ada (OPDS `Summary`), fallback layar 12 tetep buat buku tanpa summary.
- "App di latar: notifikasi lokal" bentrok sama keputusan download foreground; coret, atau buka lagi `background_downloader`.
- Layar 17 (tips pakai kalimat pembuka buku yang lagi diunduh) cuma buat buku kurasi yang kalimatnya di-hardcode.
- Bottom bar Rak · Cari buku · Atur = revamp navigasi seluruh app; issue sendiri, prasyarat #167.
- Paging ikut OPDS: 25, bukan 20.

## Ditunda

- **Standard Ebooks** ([#168](https://github.com/choiruladamm/luma/issues/168)): adapter OPDS + Basic auth, kredensial di `flutter_secure_storage`. Dibuka kalau ikut Patrons Circle.
- **Backend aggregator** ([#168](https://github.com/choiruladamm/luma/issues/168)): dibuka kalau ada user lain atau kena rate limit.
