# Luma

EPUB reader iOS (dipakai sendiri, dogfooding): tap paragraf → terjemahan Indonesia + makna dari LLM, tanpa keluar halaman baca.

## Sumber kebenaran

- **Produk, data model, alur:** [docs/ideas-mvp-apps-reading-book.md](docs/ideas-mvp-apps-reading-book.md). Baca bagian yang relevan sebelum mengerjakan fitur apa pun. Bagian 12 ke bawah (Recap, Markdown, PDF) di luar scope: kerjakan hanya kalau diminta.
- **Desain UI:** Stabilo di Claude Design, https://claude.ai/artifact/EBwv9zJBLZQJa5WWYiaJ7F. Baca board layar yang dikerjakan (nama board tercantum di issue) lewat Artifact tool, bukan WebFetch. Tiap layar punya versi terang + gelap.
- **Task:** GitHub issues milestone `MVP`, label `area:*`. Satu issue = satu unit kerja. Cek baris **Tergantung** di issue dan pastikan dependensinya sudah selesai. Centang checklist scope saat selesai.

## Urutan kerja

Urutan issue (alur utuh dulu, fitur inti sebelum pemanis, backup sebelum dogfooding karena app di-install ulang tiap 7 hari):

1. Fondasi UI: #1 → #2 → #3
2. Fondasi data: #4 → #5 → #6 → #7
3. Import: #8 → #9 → #10
4. Rak: #30 → #12 → #11
5. Baca: #13 → #14 → #17 → #19 → #32 → #18 → #33
6. Fitur inti: #20 → #21 → #22 → #23
7. Pengaman data: #24 → #25 → #26
8. Pemanis: #15 → #16 → #31 → #27
9. Validasi: #40 → #28 (boleh kapan aja setelah #21; abis #40 biar dievaluasi pakai prompt baru) → #29

Issue baru disisipin di fase yang cocok di daftar ini.

Kalau user bilang "next task" / "lanjut":
1. `gh issue list --milestone MVP --state open` → ambil issue open pertama di urutan di atas yang semua **Tergantung**-nya udah closed.
2. Sebutin nomor, judul, dan ringkasan scope-nya, terus tunggu user confirm. Jangan langsung ngoding.
3. Setelah confirm: baca docs + board yang disebut issue, kerjain, `make check`, commit `Closes #N`, centang checklist, push.

## Project

App Flutter di `apps/mobile`, Flutter dikunci lewat `.fvmrc`. Jalankan perintah lewat `Makefile` di root (`make help` untuk daftar); di luar itu pakai `fvm flutter` / `fvm dart` dari `apps/mobile`.

- Setelah ubah tabel Drift atau model freezed: `make gen`. File `*.g.dart` / `*.freezed.dart` ikut di-commit.
- Schema Drift: udah ada data di iPhone, jadi tiap ubah tabel wajib naikin `schemaVersion` + langkah di `onUpgrade` + test di `test/data/migration_test.dart` (fixture SQL versi lama, bandingin schema hasil migrasi sama install baru). Jangan minta user hapus app. `drift_dev make-migrations` gak bisa dipakai: kolom `paragraphs.text` bikin kode snapshot-nya gagal compile.
- `make check` (format, analyze, test) harus bersih sebelum commit.
- `make run` / `make release` ke device hanya kalau user minta.

## Arsitektur

Layered (UI → data), struktur hybrid:

```
lib/
├── data/database/      # Drift AppDatabase + appDatabaseProvider
├── data/services/      # file storage, OpenRouter, secure storage
├── data/repositories/  # sumber kebenaran, ubah data mentah → domain model
├── domain/             # logika pure (grouping, parser); models/ = model immutable (freezed)
├── routing/router.dart # routerProvider + Routes
└── ui/
    ├── core/           # theme Stabilo, widget shared
    └── features/<fitur>/{views,view_models}/   # layar = <Nama>View di <nama>_view.dart
```

- State: Riverpod 3, provider ditulis manual (tanpa `riverpod_generator`, sama seperti Mibu), dideklarasikan di sebelah class yang diekspos. `Notifier` berperan sebagai ViewModel. Pakai `.autoDispose` untuk state per layar; service/DB tanpa autoDispose.
- Nama provider utama sudah ditetapkan di docs bagian 8 (`booksStreamProvider`, `groupAiProvider`, dll): pakai nama itu.
- Routing: go_router, hanya `/`, `/reader/:bookId`, `/settings`; navigasi pakai konstanta `Routes`, bukan string. Sheet artinya, Aa, daftar isi = `showModalBottomSheet`.
- Warna dari `context.stabilo`, teks dari `StabiloType`, ukuran/radius/gerak/bayangan dari `stabilo_tokens.dart` (`Space`, `Radii`, `Layout`, `Motion`, `Elevation`). Tanpa hex atau angka ajaib di widget; token baru ditambah di sana dulu.
- Komponen shared di `ui/core/widgets/`, pakai ulang (ukuran khusus komponen boleh ditulis di sana): `AppButton.primary/secondary/danger`, `CircleButton`, `AppIcon` + `AppIcons` (Hugeicons Stroke Rounded), `Tag.section/status`, `showAppSheet` + `SheetFrame`, `showToast`, `showConfirmDialog`, `showAppMenu`, `AppField`, `BookCover` (cover asli / default dari judul), `BookCard`. Komponen khusus satu fitur tinggal di folder fiturnya.

## Skill Flutter

Load hanya skill yang dibutuhkan kerjaan saat itu:

- `flutter-apply-architecture-best-practices`: fitur baru yang menyentuh data/repository/ViewModel, atau refactor struktur.
- `flutter-setup-declarative-routing`: ubah route/navigasi.
- `flutter-build-responsive-layout`: layout yang rusak di ukuran layar tertentu.
- `flutter-add-widget-test`: nulis widget test layar/komponen.

Kalau skill bentrok dengan file ini, ikuti file ini (architecture skill mencontohkan `ChangeNotifier` + `provider`/`get_it`, di sini pakai Riverpod).

## Test

Struktur folder ikut Mibu (`choiruladamm/mibu`, `apps/mobile/test/`), tapi **widget test gak pernah nyentuh Drift** (di Mibu itu bikin test nyangkut). Tiap issue selesai bawa test-nya:

- `test/domain/`: logika pure (grouping, parser, cover, parsing JSON LLM, persentase baca).
- `test/data/`: repository, schema, dan **stream Drift** pake `test()` biasa (event loop asli), DB in-memory `AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true))`. Round-trip backup/restore masuk sini.
- `test/ui/core/`: widget shared.
- `test/ui/features/<fitur>/<layar>_test.dart`: widget test per layar. Override **provider view-model** (mis. `booksStreamProvider.overrideWith((ref) => controller.stream)`) pake data palsu, bukan DB. Service luar (OpenRouter, file picker, secure storage) juga fake.

Jebakan widget test:
- `testWidgets` jalan di jam palsu: stream Drift, file IO, dan decode gambar butuh event loop asli. Stream Drift → override provider-nya. File/gambar → bungkus `pumpWidget` + tunggu di `tester.runAsync`, baru `pump()`.
- `make test` pake `--timeout 30s`: test yang nyangkut gagal, gak macet. Jangan naikin timeout buat nutupin hang; cari yang nunggu event loop asli.
- `--timeout` cuma motong **test**, bukan tearDown / proses yang gak mau keluar. Dua penyebab nyangkut yang udah kejadian:
  - `tearDown(() => controller.close())` pada `StreamController` yang didengerin app: kalau test gagal di tengah, `close()` nunggu selamanya. Tulis `tearDown(() => unawaited(controller.close()))`.
  - Provider yang baca DB lupa di-override: `appDatabaseProvider` sengaja `throw` di `flutter test` (cek `FLUTTER_TEST`) biar gagal cepat, bukan buka DB beneran yang nahan proses. Buka layar baru di test → override provider layar itu juga.
- Jalanin suite penuh di background + pantau log; kalau log diam > 20 detik, itu nyangkut, bukan lambat.
- Font test = Ahem (1em per glyph): set `tester.view.physicalSize = Size(900, 1400)`, `devicePixelRatio = 1`, `addTearDown(tester.view.reset)` supaya gak overflow palsu. Butuh ukuran teks asli (layout cover)? Load font-nya pake `FontLoader` di `setUpAll`.
- `test/flutter_test_config.dart` set `driftRuntimeOptions.dontWarnAboutMultipleDatabases = true` (tiap test buka DB sendiri).

Integration test di luar scope MVP.

## Aturan data yang gampang terlewat

- DB hanya menyimpan **nama file**; path absolut di-resolve saat runtime (container iOS berubah tiap reinstall).
- Tabel lain menunjuk `chapters.id`, bukan urutan chapter.
- `paragraphIndex` & `groupIndex` harus stabil. Ubah logika parsing/grouping → naikkan `parserVersion`, re-import, hapus `ai_results` buku itu.
- Data yang ikut backup disimpan di Drift (tabel `settings`). API key hanya di `flutter_secure_storage` dan tidak ikut backup.
- Parsing EPUB dan zip backup jalan di isolate.
- Model LLM dibaca dari Pengaturan, reasoning dimatikan, output JSON divalidasi (bagian 9).

## Copy

UI berbahasa Indonesia gaya Gen Z santai ("Rak buku lo", "Bentar, lagi mikir..."). Ambil teks persis dari board desain kalau ada.

## Git

- Conventional Commits (`feat(reader): ...`, `fix(import): ...`), scope = area. Tutup issue lewat `Closes #N` di commit/PR.
- Tanpa `Co-Authored-By` atau tanda AI apa pun di commit, PR, dan issue.
- Repo public: link desain selalu tanpa parameter `?sk=`.
