# Luma

Reader buku iOS + Android (EPUB, Markdown; dipakai sendiri, dogfooding): tap paragraf → terjemahan Indonesia + makna dari LLM, tanpa keluar halaman baca.

## Sumber kebenaran

- **Produk, data model, alur:** [docs/](docs/README.md), satu file per topik (indeks di `docs/README.md`). Baca file yang relevan sebelum mengerjakan fitur apa pun. `docs/ideas/` (Recap, ide raw) dikerjakan hanya kalau diminta. Rujuk docs pakai path file (`docs/llm.md`), bukan nomor bagian.
- **Desain UI:** Stabilo di Claude Design, https://claude.ai/artifact/EBwv9zJBLZQJa5WWYiaJ7F. Baca board layar yang dikerjakan (nama board tercantum di issue) lewat Artifact tool, bukan WebFetch. Tiap layar punya versi terang + gelap.
- **Task:** GitHub issues, label `area:*`. Satu issue = satu unit kerja. Semua dependensi di baris **Tergantung** harus udah closed. Centang checklist scope saat selesai.

## Urutan kerja

- **MVP** (milestone `MVP`): fase 1–8 selesai, sisa #29 dogfooding.
- **Di luar MVP**, label status:
  - `status:ready`: plan jelas; mulai setelah semua dependensi closed.
  - `status:deferred`: nunggu pemicu (baris **Dibuka kalau** di issue). Pemicu kejadian → ganti ke `status:ready`.
  - `status:idea`: belum diputusin; bisa ditutup `wontfix`.
- **Integrasi existing:** Ngobrolin buku (#112) tersisa gate akhir #124; Discover (#163) seluruh anak closed, acceptance akhir belum tercatat lengkap. Status closed/merged tidak menggantikan bukti device.
- **Induk berurutan:**
  - Import PDF langsung (induk #83): selesai, merged lewat #193. Sisa ditunda di `status:deferred` (#90 password, #91 OCR, #92 rapikan LLM, #93 preview bab, #94 layout kolom/sidebar, rencana di issue itu); Android dan tap Artinya di PDF belum diuji terpisah.
  - Import PDF lewat Markdown: sisa #78 (uji PDF asli).
  - Statistik (induk #42): tampilan #50–#58 nunggu data ngumpul + desain.
  - Backend Cloudflare (induk #197): #198 scaffold → #199 auth backend (UI + Google di #211, nunggu board) → #200 key AI → #201 backup cloud → #109 sync push → #210 sync pull. Kerja di branch `feat/backend` (di-push, belum ke `master`), alur per issue: `docs/backend.md` (Alur kerja per issue). Sisa `status:deferred`: #106, #202–#209.
- Issue / ide / item ditunda baru: bikin issue dengan label status yang cocok, sisipin di induk yang cocok, tambah link `(#N)` di docs-nya.

## Project

App Flutter di `apps/mobile`, Flutter dikunci lewat `.fvmrc`. Perintah lewat `Makefile` di root (`make help`); di luar itu `fvm flutter` / `fvm dart` dari `apps/mobile`. Backend Worker di `apps/backend` (Bun + Wrangler): `make backend-dev` / `backend-test` / `backend-deploy e=dev`, setup akun di `docs/backend.md` (Setup & deploy).

- Setelah ubah tabel Drift atau model freezed: `make gen`. File `*.g.dart` / `*.freezed.dart` ikut di-commit.
- Schema Drift: udah ada data di iPhone, jadi tiap ubah tabel wajib naikin `schemaVersion` + langkah di `onUpgrade` + test di `test/data/migration_test.dart` (fixture SQL versi lama, bandingin schema hasil migrasi sama install baru). Data user dipertahankan lewat migrasi, gak pernah lewat hapus app. `drift_dev make-migrations` gak bisa dipakai: kolom `paragraphs.text` bikin kode snapshot-nya gagal compile.
- **Run only the tests relevant to what you changed.** The suite is large and slow (1200+ tests, ~2 min) and keeps growing. Do not run the whole suite by default.
  - Small fixes, tweaks, and features that do not touch other features: run `dart format` and `dart analyze` on the touched files, plus only the tests that cover the changed code (`fvm flutter test <test files or dirs> --timeout 30s`, e.g. `test/ui/features/<feature>`, `test/ui/core/<widget>_test.dart`, `test/data/<repo>_test.dart`).
  - Run full `make check` (format, analyze, all tests) only for major or wide changes: Drift schema/migrations, models/codegen, shared widgets used across features, routing/theme, or many features at once.
  - Never re-run the full suite just to re-confirm a small follow-up fix.
  - Commit only when the checks you ran exit 0 (never chain a commit behind `grep` or `;`). State in the hand-off which checks ran and that the full suite was not run.

### Build ke device

Dua app terpisah (data & Keychain sendiri-sendiri):

| App | Bundle id | iOS | Android | Dari |
|---|---|---|---|---|
| **Luma** (data asli user) | `id.ruma.luma` | `make release` | `make release-android`, `make apk` | `master` doang |
| **Luma Dev** (ikon hitam) | `id.ruma.luma.dev` | `make dev`, debug `make run f=dev` | `make dev-android`, debug `make run-android f=dev` | branch fitur |

Branch fitur selalu ke Luma Dev: migrasi schema yang belum stabil bakal nyentuh data asli, dan Drift gak bisa turun versi. Android selalu pakai `--flavor` (`prod` / `dev`); release ditandatangani keystore tetap lewat `android/key.properties` (gitignored, lihat README), tanpa siklus 7 hari. Detail: `docs/architecture.md` (Gotcha platform).

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

- State: Riverpod 3, provider ditulis manual (tanpa `riverpod_generator`), dideklarasikan di sebelah class yang diekspos. `Notifier` = ViewModel. `.autoDispose` untuk state per layar; service/DB tanpa autoDispose.
- Nama provider utama udah ditetapkan di `docs/architecture.md` (`booksStreamProvider`, `groupAiProvider`, dll): pakai nama itu.
- Routing: go_router. Shell tab Rak · Cari buku · Atur (`/`, `/discover`, `/settings`, bar `LumaNavBar` di `AppShell`), di luar shell `/reader/:bookId`, `/reader/:bookId/breakdown/:chapterId/:groupIndex` (Bedahin, cuma di-push dari sheet Artinya), chat; navigasi pakai konstanta `Routes`. Sheet artinya, Aa, daftar isi = `showModalBottomSheet`.
- Warna dari `context.stabilo`, teks dari `StabiloType`, ukuran/radius/gerak/bayangan dari `stabilo_tokens.dart` (`Space`, `Radii`, `Layout`, `Motion`, `Elevation`). Widget cuma pakai token; nilai baru ditambah jadi token di sana dulu.
- Komponen shared di `ui/core/widgets/`, pakai ulang (ukuran khusus komponen boleh ditulis di sana): `AppButton.primary/secondary/danger`, `CircleButton`, `AppIcon` + `AppIcons` (Hugeicons Stroke Rounded), `Tag.section/status`, `showAppSheet` + `SheetFrame`, `showToast`, `showConfirmDialog`, `showAppMenu`, `AppField`, `BookCover` (cover asli / default dari judul), `BookCard`, `StatusButton` / `StatusCard` / `IconTile` / `Skeleton` (status jawaban AI, sheet Artinya + Bedahin). Komponen khusus satu fitur tinggal di folder fiturnya.

## Skill Flutter

Load hanya skill yang dibutuhkan kerjaan saat itu:

- `flutter-apply-architecture-best-practices`: fitur baru yang menyentuh data/repository/ViewModel, atau refactor struktur.
- `flutter-setup-declarative-routing`: ubah route/navigasi.
- `flutter-build-responsive-layout`: layout yang rusak di ukuran layar tertentu.
- `flutter-add-widget-test`: nulis widget test layar/komponen.

Skill bentrok dengan file ini → ikuti file ini (architecture skill mencontohkan `ChangeNotifier` + `provider`/`get_it`, di sini Riverpod).

## Kode Dart: logika kondisional

- Ternary maksimal 1 level di widget tree.
- Kondisi lebih dari 2 cabang, atau label/teks dari state model: extract ke getter di extension pada model (contoh: `book.progressLabel`), isinya `if/return` berurutan.
- State yang bisa nambah: enum + switch expression.

## Test

Struktur folder ikut Mibu (`choiruladamm/mibu`, `apps/mobile/test/`), tapi **widget test gak pernah nyentuh Drift** (di Mibu itu bikin test nyangkut). Tiap issue selesai bawa test-nya:

- `test/domain/`: logika pure (grouping, parser, cover, parsing JSON LLM, persentase baca).
- `test/data/`: repository, schema, dan **stream Drift** pake `test()` biasa (event loop asli), DB in-memory `AppDatabase(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true))`. Round-trip backup/restore masuk sini.
- `test/ui/core/`: widget shared.
- `test/ui/features/<fitur>/<layar>_test.dart`: widget test per layar. Override **provider view-model** (mis. `booksStreamProvider.overrideWith((ref) => controller.stream)`) pake data palsu, bukan DB. Service luar (OpenRouter, file picker, secure storage) juga fake.

Jebakan widget test:
- `testWidgets` jalan di jam palsu: stream Drift, file IO, dan decode gambar butuh event loop asli. Stream Drift → override provider-nya. File/gambar → bungkus `pumpWidget` + tunggu di `tester.runAsync`, baru `pump()`.
- `make test` pake `--timeout 30s`: test yang nyangkut gagal, gak macet. Test nyangkut = cari yang nunggu event loop asli, timeout tetap 30s.
- `--timeout` cuma motong **test**, bukan tearDown / proses yang gak mau keluar. Dua penyebab nyangkut yang udah kejadian:
  - `StreamController` yang didengerin app: tulis `tearDown(() => unawaited(controller.close()))`. `close()` yang di-await nunggu selamanya kalau test gagal di tengah.
  - Provider yang baca DB lupa di-override: `appDatabaseProvider` sengaja `throw` di `flutter test` (cek `FLUTTER_TEST`) biar gagal cepat. Buka layar baru di test → override provider layar itu juga.
- Jalanin suite penuh di background + pantau log; log diam > 20 detik = nyangkut, bukan lambat.
- Font test = Ahem (1em per glyph): set `tester.view.physicalSize = Size(900, 1400)`, `devicePixelRatio = 1`, `addTearDown(tester.view.reset)` supaya gak overflow palsu. Butuh ukuran teks asli (layout cover)? Load font-nya pake `FontLoader` di `setUpAll`.
- `test/flutter_test_config.dart` set `driftRuntimeOptions.dontWarnAboutMultipleDatabases = true` (tiap test buka DB sendiri).

Integration test di luar scope MVP.

## Aturan data yang gampang terlewat

- DB hanya menyimpan **nama file**; path absolut di-resolve saat runtime (container iOS berubah tiap reinstall).
- Tabel lain menunjuk `chapters.id`, bukan urutan chapter.
- `paragraphIndex` & `groupIndex` harus stabil. Ubah logika parsing/grouping → naikkan `parserVersion`, re-import, hapus `ai_results` buku itu.
- Data yang ikut backup disimpan di Drift (tabel `settings`). API key hanya di `flutter_secure_storage`, gak ikut backup.
- Parsing EPUB dan zip backup jalan di isolate.
- Index Cari kata (`paragraph_fts`, FTS5 external-content) nempel ke rowid `paragraphs` dan dijaga trigger. Jangan nulis ke `paragraphs` dengan trigger dimatiin, dan habis `VACUUM` / ganti file DB wajib `rebuildBookSearchIndex()` (restore udah). Detail: `docs/book-search.md`.
- Model LLM dibaca dari Pengaturan, reasoning dimatikan, output JSON divalidasi (`docs/llm.md`).
- Backend (`apps/backend`) dan kode client yang memanggilnya wajib muat free tier Cloudflare: tanpa polling, debounce/batch, retry terbatas, stream file. Tiap perubahan pemanggilan backend perbarui tabel anggaran di `docs/backend.md` (Aturan free tier).

## Copy

UI mendukung Indonesia / English lewat `lib/l10n/app_id.arb` (template) dan `app_en.arb`; akses dari UI lewat `context.l10n`. Copy Indonesia tetap gaya Gen Z santai ("Rak buku lo", "Bentar, lagi mikir...") dan mengikuti board desain; English santai dan natural. Tambah kalimat utuh dengan placeholder/plural, lalu `make l10n`; generated source ikut di-commit. Angka/tanggal pakai formatter dengan locale eksplisit. Bahasa AI, teks buku, input user, dan jejak chat tersimpan tetap bahasa asal. Detail: [docs/i18n.md](docs/i18n.md).
