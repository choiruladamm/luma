# Arsitektur & Alur

## Routing (go_router)

- `/` → Rak buku
- `/reader/:bookId` → Halaman baca (posisi dari `reading_progress`)
- `/reader/:bookId/breakdown/:chapterId/:groupIndex` → Bedahin satu grup (`Routes.breakdown`). Cuma di-`push` dari sheet Artinya: sheet tetep di bawah, balik = balik ke sheet. "Balik baca" = `pop(true)`, yang manggil (`ReaderView`) ikut nutup sheet-nya, jadi langsung ke halaman.
- `/settings` → Pengaturan (termasuk bagian Backup & restore)
- Bottom sheet artinya, Aa, dan Daftar isi **bukan route**, cukup `showModalBottomSheet`.

## Provider utama (Riverpod)

- `booksStreamProvider` → `StreamProvider` dari query Drift, untuk grid rak.
- `chapterParagraphsProvider(chapterId)` → paragraf satu chapter dari Drift.
- `bookChaptersProvider(bookId)` → daftar chapter terurut `sortOrder` (untuk Daftar isi).
- `groupAiProvider(GroupRef)` → `FutureProvider.autoDispose.family`:
  1. Cek `ai_results`
  2. Kalau belum ada: ambil paragraf grup + sampe 3 paragraf (bukan heading/pemisah) sebelum paragraf pertama grup di chapter yang sama sebagai konteks
  3. Panggil LLM (API key dibaca dari Keychain / Keystore, model dari `ai.model`)
  4. Validasi jumlah `translations` = jumlah paragraf grup
  5. Simpan ke Drift, return hasil

  **Auto-retry Riverpod 3 dimatiin** (`retry: (_, _) => null`): tiap percobaan motong saldo. Gagal → `AsyncError` berisi `AiException`, dicoba ulang cuma lewat `ref.invalidate` (tombol "Coba lagi"). Hasil tetep disimpen walaupun sheet keburu ditutup. Dua tap ke grup yang sama pas lagi loading = satu request.
- `groupAiStreamProvider(GroupRef)` → `NotifierProvider.autoDispose.family` (`GroupAiStream`), versi streaming yang dipakai sheet Artinya. State `AiStream`: `phase` (`AiPhase`), `draft` (teks yang udah dateng, belum di-pacing), `sources` (panjang paragraf asli buat placeholder), `error`, `cached`.
  1. Cache dulu → langsung `done` (`cached`), gak manggil LLM.
  2. Belum ada → stream jawaban bersection ([llm.md](llm.md)), state `waiting` → `translating` → `meaning` → `done`; cabang `slow` (15 detik tanpa token, request tetep jalan; token masuk → `translating`), `failed` (30 detik tanpa token = `timeout`, gak ada key, HTTP, dll), `cut` (putus, atau token berhenti 20 detik di tengah; teks yang udah masuk tetep di `draft`).
  3. Lengkap → validasi; gak valid → sekali lagi lewat jalur JSON tanpa streaming (`explain(attempts: 1)`). Disimpen cuma kalau lengkap dan valid.
  4. **Beda sama `groupAiProvider`:** ke-dispose (tutup sheet, Lanjut ke grup lain) = request dibatalin (`CancelToken`) dan gak ada yang disimpen; ngulang satu grup cuma pecahan sen. Dua tap ke grup yang sama tetep satu request (family). Coba lagi = `ref.invalidate`, mulai lagi dari `waiting`. Kalau pas dogfooding sering kebuka-tutup gak sengaja: tambah masa tenggang (request jalan 2–3 detik abis sheet ditutup).
- `breakdownStreamProvider(GroupRef)` → `NotifierProvider.autoDispose.family` (`BreakdownStream`, di `reader/view_models/breakdown_view_model.dart`), sumber layar Bedahin ([llm.md](llm.md#bedahin-60)). State `BreakdownState`: `phase` (`BreakdownPhase`), `input` (terjemahan yang dibedah, buat panel teks), `draft` (`Breakdown`), `error`, `cached`.
  1. Bahan dari `AiBreakdownsRepository.input`: terjemahan + makna `ai_results` (gak ada = `failed`, harusnya gak kejadian dari UI), teks asli grup, sampe 3 paragraf konteks, teks asli grup berikutnya, judul semua bab urut `sortOrder`.
  2. Cache `ai_breakdowns` valid (versi + `sourceHash` terjemahan sekarang) → langsung `done` (`cached`).
  3. Belum ada → stream, `waiting` → `writing` → `done`; cabang `slow`, `failed`, `cut` dengan ambang yang sama kayak `groupAiStreamProvider`.
  4. Lengkap → `parseBreakdown`; gak valid → di-stream sekali lagi (bukan jalur JSON), masih gagal → `failed(invalidResponse)`. Disimpen cuma kalau valid, abis itu `breakdownSectionsProvider` grup itu di-refresh.
  5. Ke-dispose (tutup layar) = `CancelToken`, gak ada yang disimpen. Coba lagi = `ref.invalidate`.
- `breakdownSectionsProvider(GroupRef)` → `FutureProvider.autoDispose.family<int>`: jumlah bagian bedahan grup ini yang masih berlaku, 0 = belum ada (entri "Buka bedahan · N bagian" di sheet Artinya).
- `breakdownPeekProvider(PeekKey)` → `FutureProvider.autoDispose.family<BreakdownPeek?>`, `PeekKey = ({GroupRef from, int? chapter})`: tujuan kartu Nyambung ke (`AiBreakdownsRepository.peek`). `B<n>` = grup pertama chapter ke-n (urut `sortOrder`), null = grup berikutnya di chapter yang sama. Isinya teks asli + terjemahan `ai_results` kalau ada. Null = tujuan gak ada, kartu jadi teks biasa.
- `importControllerProvider` → `Notifier` untuk state import (idle / processing / success / error / duplicate).

`GroupRef` = record `({int chapterId, int groupIndex})`: `==`/`hashCode` per nilai udah bawaan Dart, gak perlu `freezed`.

## Alur import

1. Pilih file EPUB via `file_picker`
2. Baca bytes, hitung SHA-256 → kalau hash sudah ada → state **duplikat**
3. Parse EPUB di isolate (parser sendiri): judul, penulis, cover, chapter dari TOC/nav (bukan dari jumlah file HTML), `sortOrder` = urutan TOC. **Parse dulu sebelum nyalin file**, jadi EPUB jelek gak ninggalin apa-apa
4. Per chapter: parse HTML (package `html`), ambil blok teks (`p`, `div` berisi teks, heading, `hr`), normalisasi whitespace, buang paragraf kosong, lewati bagian non-isi (lihat [raw.md](ideas/raw.md))
5. Jalankan `assignGroups` per chapter
6. Copy ke `Documents/books/{hash}.epub`, cover ke `Documents/covers/{hash}.{ext}`
7. Insert `books` + `chapters` + `paragraphs` dalam **satu transaksi** Drift
8. Gagal setelah nyalin → hapus file yang sudah di-copy (transaksi di-rollback), state **error**

Parsing buku besar bisa berat: jalankan di isolate (`compute` / `Isolate.run`) supaya UI tidak freeze.

## Posisi baca

- **Titik acuan** = paragraf paling atas yang keliatan di bawah safe area atas + `paragraphOffset` (bagian paragraf itu yang udah lewat garis tersebut, fraksi 0–1).
- **Nyimpen**: cuma setelah scroll dari jari (lompatan restore gak dihitung), debounce ±500 ms setelah scroll berhenti. Langsung disimpen pas app ke background (`AppLifecycleState` selain `resumed`), pindah bab, dan keluar halaman baca. Gak pernah nulis ke DB tiap frame.
- **Restore** (buka buku): lompat ke paragraf tersimpan, terus geser sesuai offset supaya titiknya ada di ±⅓ tinggi layar (ada konteks di atasnya). Tinggi paragraf baru ketahuan setelah layout, jadi dihitung di post-frame callback; isi bab disembunyiin sampe udah di posisi, terus fade in. Kepotong di ujung scroll kalau titiknya deket akhir chapter.
- Satu chapter dirender utuh (bukan list lazy), jadi posisi semua paragraf ketahuan tanpa package tambahan.

## Perilaku kapsul baca

- Scroll turun ≥ 24pt → dua kapsul geser keluar (200 ms, ease-out). Naik ≥ 12pt atau flick ke atas → muncul. Selama jari masih nge-drag, kapsul ngikutin 1:1, terus snap pas dilepas. Ambang dihitung per arah (ganti arah = mulai dari 0).
- Awal bab (80pt pertama) dan akhir bab (paragraf terakhir keliatan) → kapsul muncul sendiri. Pindah bab → muncul.
- Cuma scroll dari jari yang dihitung; lompatan restore posisi gak ngumpetin kapsul.
- **Zona tap**: paragraf → sheet Artinya (kotak paragraf selebar kolom teks, termasuk sisa kosong di baris pendek). Area kosong (margin kiri-kanan, sela antar paragraf, di bawah teks terakhir, heading/pemisah adegan) → munculin/ngumpetin kapsul. Tengah layar gak punya fungsi khusus. Tap kosong pas sheet kebuka → nutup sheet (barrier sheet).
- **Sheet dari kapsul (Daftar isi, Aa)**: kapsul atas tetep keliatan di atas scrim, tombol yang sheet-nya kebuka jadi kuning, tap tombol itu lagi = nutup sheet. Sheet mulai 12pt di bawah kapsul. Implementasinya: barrier sheet transparan, scrim digambar halaman baca di bawah kapsul; tap di area kapsul kena barrier → sheet ketutup.
- **Sheet Artinya** (dibuka dari teks): kapsul ngumpet; halaman di-scroll barengan sheet naik sampe bawah blok grup = atas sheet − 16pt, termasuk tiap tinggi sheet berubah (loading → hasil / error / API key kosong). Grup kepanjangan: atas blok = safe area + 16pt. "Lanjut" mindahin highlight ke grup berikutnya di bab itu (grup terakhir: tombolnya mati) dan nge-scroll grup itu ke atas sheet; pas ditutup halaman diem di grup terakhir dan posisinya disimpen. Cuma buka satu grup → halaman balik ke posisi sebelum sheet dibuka.
  - Grup yang dibuka: satu blok stabilo (`highlight`, radius 14) melebar setengah margin ke samping & 8pt atas-bawah, teksnya `onHighlight`. Scrim 38% digambar halaman baca dan **dibolongin** pas di blok itu, jadi grupnya kebaca di atas scrim; barrier sheet transparan, tap di luar sheet = nutup.
  - Tinggi sheet tetap 62,5% layar (528 di 844) di semua state, `DraggableScrollableSheet` (min 0, snap): tarik turun di isi pas offset 0 atau di grabber nutup sheet. Isi scroll setinggi sheet (EdgeFade 20pt), header ikut ke-scroll, grabber dan tombol (Salin / Lanjut) lapisan di atas isi, padding isi atas 91 / bawah 102. Error dan API key kosong juga 528 (tombol nempel di bawah).
  - State: loading ("Bentar, lagi mikir..." + titik berdenyut, skeleton shimmer, tombol mati), hasil (Terjemahan per paragraf + "Maksud penulisnya tuh...", Salin + Lanjut), error ("Yah, gagal nih" + kode kecil: `timeout · 30 detik`, `offline / gak nyambung`, `HTTP 401 · key ditolak`, `HTTP 402 · saldo abis`, `HTTP n`, `jawaban AI gak valid`; "Coba lagi" = `ref.invalidate`), API key kosong ("Isi API key dulu yuk" → Pengaturan). Terjemahan belum di-stream (API dipanggil tanpa streaming), jadi loading-nya skeleton dua section.
  - "Salin" nyalin terjemahan seluruh grup (satu paragraf per blok), tombolnya jadi "Disalin" + toast "Udah disalin, tinggal paste" di atas sheet.
  - **Penanda grup** yang udah diterjemahin (ParagraphMark): garis 4pt warna `mark` di tengah margin kiri, sepanjang grup (inset 5pt). Grup itu langsung keisi dari cache pas di-tap.
- **Akhir bab**: kartu akhir bab keliatan → dua kapsul muncul, kapsul bawah nulis "<judul bab> kelar". **Akhir buku**: layar sendiri tanpa kapsul, garis progres penuh 100%, cover pake cover default (tanpa bulatan huruf), status bar balik.
- **Lanjut baca** (buka buku yang ada posisi tersimpannya): kapsul muncul 2,5 detik buat orientasi terus ngumpet sendiri (batal kalau user udah scroll duluan). Grup tempat posisi tersimpan dikasih kilatan stabilo sekali, 0 → 60% → 0 dalam 1,2 detik. "Kurangi gerakan" iOS nyala → tanpa kilatan, gantinya garis kiri 4pt yang ilang setelah 3 detik.
- Status bar ngumpet bareng kapsul kalau toggle "Sembunyiin jam & baterai" nyala (default nyala; togglenya di Aa, #18). Keluar halaman baca → status bar balik.

## Persentase baca

`(chapters.charOffset + jumlah karakter paragraf sebelum posisi) / books.totalChars`.

Buku Markdown ([import-formats.md](import-formats.md)) totalnya cuma bab yang sudah masuk, jadi persentase bisa turun tiap bab baru masuk. Kartu Rak-nya pakai strip bab dan chip "N bab", bukan persen, dan tidak pernah "Kelar!".

## Gotcha platform

### iOS

- **Dua app: Luma & Luma Dev.** Scheme `Runner` (config `Debug`/`Release`/`Profile`) = Luma, `id.ruma.luma`, dipake baca tiap hari, cuma dari `master` (`make release`). Scheme `dev` (config `Debug-dev`/`Release-dev`/`Profile-dev`) = Luma Dev, `id.ruma.luma.dev`, ikon `AppIcon-dev` (varian tinted), nama dari `APP_DISPLAY_NAME`; branch fitur dicoba di sini (`make dev`). Container Documents + Keychain per bundle id, jadi data, DB (schema bisa lebih baru), dan API key terpisah; key diisi ulang sekali di Luma Dev. Data asli bisa dibawa lewat backup Luma → restore di Luma Dev (gak bisa sebaliknya kalau schema Luma Dev lebih baru). Akun Apple gratis: maks 3 app sideload aktif (Luma + Luma Dev = 2), 10 App ID baru per 7 hari, dua-duanya di-install ulang tiap 7 hari. Ikon dev ikut `make brand`.

- **Jangan simpan absolute path di database.** Path container app iOS bisa berubah setiap update/reinstall. Simpan nama file, gabungkan dengan `getApplicationDocumentsDirectory()` saat runtime.
- File dari picker biasanya ada di folder sementara, jadi wajib di-copy ke Documents.
- Buat folder `books/` dan `covers/` saat app start (`create(recursive: true)`).

### Android

- **Dua app, kayak iOS.** Flavor `prod` = Luma (`id.ruma.luma`, label "Luma"), flavor `dev` = Luma Dev (`id.ruma.luma.dev`, label "Luma Dev", ikon hitam). Label dari `resValue app_name` di `build.gradle.kts`. Data + Keystore per application id. `flutter run` / `build` wajib `--flavor`; target Makefile Android (`run-android`, `dev-android`, `release-android`, `apk`) selalu ngirimnya. Aturan sama: branch fitur cuma ke Luma Dev, `release-android` / `apk` cuma dari `master`.
- **Signing tetap.** Update APK (`install -r`) cuma jalan kalau key-nya sama. `android/key.properties` (gitignored) nunjuk ke keystore di luar repo; tanpa itu release jatuh ke debug key (langkah bikin keystore di README). Gak ada siklus 7 hari di Android; banner backup 6 hari tetap dipakai.
- **`allowBackup="false"`** + `data_extraction_rules.xml` yang ngeluarin semuanya: prefs terenkripsi `flutter_secure_storage` gak boleh ke-restore ke HP lain tanpa master key-nya (key rusak), dan data Luma dibackup lewat fitur backup sendiri.
- **Status share.** Di Android `share_plus` bisa balik `unavailable` (target share gak ngasih hasil). `shareSaved` nganggep `unavailable` = sukses di Android supaya `backup.lastAt` tetap kecatet; `dismissed` = batal.
- **Edge-to-edge** (Android 15+ dipaksa): ngumpetin status bar lewat `SystemChrome` sama kayak iOS; konten pakai `SafeArea` / `MediaQuery.padding`. Splash: system splash Android 12+ polos, warnanya sama dengan `LaunchBackground` iOS dan overlay Flutter (`values/colors.xml`, `values-night/colors.xml`).
- **Font "Bawaan sistem"**: SF (`CupertinoSystemText`) di iOS, Roboto di Android (`readingFamily`).
- Buka `.epub` dari luar app (intent filter) belum ada: iOS juga belum punya, jadi di luar scope ([#105](https://github.com/choiruladamm/luma/issues/105)).


## Ngobrolin buku: kontrak domain (#114)

Kontrak di `lib/domain/models/book_chat.dart` dan `lib/domain/chat_prompt.dart`;
[keputusan/lifecycle/state matrix #114](https://github.com/choiruladamm/luma/issues/114).
Schema 8 menyediakan tabel chat (#115). `ChatRepository` +
`chatRepositoryProvider` non-autoDispose menyediakan persistence (#116), tanpa
network. Retrieval dan transport tersedia lewat `ChatContextRepository` (#117);
ViewModel/lifecycle tersedia lewat `chatViewModelProvider` (#118); route dan UI menyusul.

`ChatBookRef` = `(bookId, contentRevision)`. Session revision lama read-only;
metadata judul/penulis/cover tidak menaikkan revision. Append/replace/reorder isi,
reparse yang mengganti identitas paragraf/bab, dan re-import harus menaikkannya
secara atomik lewat `AppDatabase.contentChanged(bookId)` (#119), dalam transaksi isi.
Import Markdown memakai hook ini setelah append/replace + renumber; fresh import
revision1. Re-import EPUB kelak wajib memakai hook yang sama. Running lama menjadi
interrupted; sesi dan snapshot history lama tetap ada.

`ChatLaunchContext` dari reader melanjutkan sesi terakhir; quote explicit dari
Artinya/Bedahin selalu draft sesi baru. Draft kosong tidak dipersist. Judul awal
berasal dari `chatTitle(question, automatic: true)`; rename manual tidak ditimpa.
`ChatReadingPosition` berbentuk record yang sama dengan `ReadingPosition` existing,
sehingga domain tidak mengimpor repository. Kunjungan sumber membawa return
position reader dan `ChatScrollAnchor` (turnId/blockIndex/alignment), tidak menulis
progres. Resolver memvalidasi owner session/turn, revision/hash/range sebelum jump.

`ChatTurn` menyimpan satu pertanyaan dan attempt yang dapat diganti hanya lewat
retry eksplisit atas turn terakhir. `ChatAttemptRef` mengikat session/turn/attempt/
book revision; repository juga wajib memeriksa session masih ada sebelum menulis.
Stop/back/switch/background memanggil cancel+flush, lalu `interrupt(cancelled: true)`;
process restart memanggil `interrupt()` menjadi interrupted. Draft tetap tersimpan,
tidak auto-send. `slow` tetap request aktif; archived merupakan relasi session vs
current revision, bukan status turn yang menghapus history. Detail persist/cancel/
stream dimiliki repository/#118, bukan model domain.

`ChatRepository` menyediakan `watchSessions(bookId)`,
`watchTurns(bookId,sessionId)`, `lastOpenedSession`, `createFirstTurn`,
`appendTurn`, `rename`, `markOpened`, `saveScrollAnchor`, `deleteSession`,
`retry`, `prepareSources`, `validatePrepared`, `checkpoint`, `finalize`, dan
`recoverInterrupted`.
Semua caller menerima model domain; mapper snapshot berada di
`data/repositories/chat_snapshot.dart`. Preview sesi hanya pertanyaan terakhir
sesi itu; urutan aktivitas `(updatedAt,id)` terpisah dari resume
`(lastOpenedAt,id)`. Stream tidak menandai sesi sebagai dibuka.

First-send membuat sesi + turn secara atomik; kegagalan validasi rollback keduanya.
Append/retry menolak pending kedua di sesi yang sama. ViewModel #118 tetap harus
menahan double tap pada draft sebelum sessionId pertama tersedia; dua panggilan
`createFirstTurn` terpisah berarti dua sesi baru. Tidak ada draft-session kosong
di database atau request ID persist tambahan.

`prepareSources` membekukan snapshot tervalidasi sebelum transport, lalu menjadi
waiting. Checkpoint menerima draft kumulatif, menolak regresi dan phase mundur;
menulis tiap ≥500ms atau pertumbuhan ≥1KiB (phase berubah langsung ditulis).
Sisa draft terbaru ditahan di memori tanpa timer; terminal `finalize` langsung
flush, termasuk tail yang belum masuk DB. True dari checkpoint berarti diterima,
bukan selalu sudah ditulis. Proses mati mendadak dapat kehilangan tail terakhir
di bawah ambang; stop/back/switch/background di #118 wajib finalize sebelum dispose.

Recovery sekali per lifetime repository berjalan sebelum read/write pertama:
persisted running/unknown phase menjadi interrupted, tanpa resend atau jaringan.
Jangan membuat repository kedua di DB yang sama ketika request masih aktif.
Setiap update attempt memeriksa session/turn ownership, revision aktif, attempt,
dan running phase dalam transaksi; terminal/attempt lama ditolak (false).
Sebelum restore menutup/mengganti DB, cancel + finalize request, lalu invalidate
provider. Provider dispose mematikan callback instance lama; callback transport
wajib menangkap instance repository asal, bukan mencari provider baru (#118/#119).


`chatContextRepositoryProvider` non-autoDispose memakai DB, `ChatRepository`,
`OpenRouterService`, dan `ApiKeyStore`. Domain retrieval di `chat_retrieval.dart`;
memakai index persist #134 tanpa framework agent baru. #118 mengambil `model()`, membuat
turn dengan `chatPromptVersion`, lalu `prepare(turn,cancel:)` → `stream(cancel:)`.
Simpan `frame.draft` dengan checkpoint writing, dan finalize done hanya untuk
`frame.answer` terakhir yang tervalidasi. Stream tanpa frame final berarti attempt
sudah tidak aktif; jangan mengubahnya menjadi not_found. Error dipetakan ke terminal
failed/cut oleh ViewModel. Embedding mempertahankan DioException cancel/certificate/
unknown agar tidak memicu fallback; #118 menangani ini bersama AiException. Semua
tahap memakai cancel yang sama. Keluar/pindah sesi/background tetap harus cancel dan finalize; repository konteks tidak memiliki lifecycle
UI atau auto-retry. Detail budget, cache dan protocol: [llm.md](llm.md).

#143: `prepare(turn, readingChapterId:)` membangun TOC dari `chapters`
(`chat_toc.dart`), mengambil context model lewat `OpenRouterService.modelInfo`
(gratis, cache per repository, fallback konservatif), lalu satu `ChatBudget`
(`chat_budget.dart`) dipakai planner, loop baca/cari, jawaban dan perbaikan
otomatis (`PreparedChat.stream`, maksimal 2). `ChatStreamFrame.repair` > 0 =
perbaikan berjalan; ViewModel menampilkan status dan menahan preview lama.
`ChatViewModel.launch` menyimpan `returnPosition.chapterId` untuk resolusi
"bab ini"; `chapterSectionBackfillProvider` dipanggil saat hydrate (lokal,
gratis) dan di-override di test tanpa DB. #150: `ChatState.explorationProgress`
(`ChatExplorationProgress`) membawa label bab + catatan; catatan dipublish lewat
`preview` existing; `answerNow()` menandai `_ChatRun` dan `canAnswerNow`
menampilkan "Jawab sekarang" selama `retrieving/slow`. #153 (Langkah AI):
`prepare(onStep:)`/`stream(onStep:)` memanggil `ChatStep` (`chat_steps.dart`:
plan/cache/read/search/skip/repair/retry/stop/answer, status done/running/skipped)
tanpa request tambahan. ViewModel menumpuk lewat `chatAppendStep` (langkah
`running` selalu terakhir, ditutup oleh langkah selesai berlabel sama) ke
`ChatState.steps` (attempt-scoped), `chatSettleSteps` menandai sisa running
sebagai skipped saat attempt berakhir tanpa jawaban, dan menyimpannya sekali
lewat `finalize(steps:)`. UI `chat_steps_row.dart` (`ChatStepsRow`, `ChatAnswerNow`)
dipasang `ChatHistory` di atas `ChatResponse`: baris status 40pt + daftar (maks 6,
"lihat N lagi"), terbuka saat jalan, tertutup setelah selesai, toggle per turn;
turn lama tanpa `steps` tidak menampilkan baris. Blok "Catatan sementara" memuat
tombol teks "Jawab sekarang →" + caption menggantikan tombol sekunder #150.


### ViewModel dan lifecycle Ngobrolin buku (#118)

`chatViewModelProvider(bookId)` adalah `NotifierProvider.autoDispose.family` manual,
satu controller per route buku. `ChatState` immutable memuat book/revision aktif,
activeSession, turns, draft, selectedQuote, phase/error/problem, loading,
changingSession dan scrollAnchor. `archived/readOnly/canSend/canRetry` diturunkan
dari state; archived bukan phase baru. `chatSessionsProvider(bookId)` terpisah
untuk daftar sesi (`AsyncValue`). `ChatRepository.watchBook` memantau revision/
penghapusan, `session(bookId,sessionId)` tetap book-scoped.

Build/hydrate/open/list/resume hanya membaca DB dan memulihkan running sebagai
interrupted lewat recovery repository. Tidak ada request berbayar. Entry reader
melanjutkan lastOpened; #120/#121 memanggil `launch(ChatLaunchContext)` **sekali dari
aksi/entry**, bukan setiap build. Quote explicit membuat draft baru tanpa record;
bisa dilepas. Launch menunggu hydrate agar quote tidak tertimpa resume. Draft
bertahan saat kembali dari Pengaturan; settings/model/key tidak memicu auto-send.

API aksi: `setDraft`, `removeQuote`, `send`, `retry`, `stop`, `openSession`,
`newSession`, `launch`, `deleteSession`, `rename`, dan `setScrollAnchor`.
`send/retry` mengembalikan Future sampai attempt terminal. Guard dipasang sebelum
await model/first insert, termasuk untuk double tap retry. Setelah turn tersimpan,
draft/quote dilepas dan controller memakai sessionId/attemptRef dari repository.
Jika stop datang saat insert belum selesai, stop menunggu hasil insert dan
memfinalisasi turn stopped; sesi yang sudah tersimpan tetap aktif jika tidak
sedang navigasi. Insert yang gagal menyisakan draft untuk dikirim ulang eksplisit.

| Pemicu | Transisi/efek |
|---|---|
| Send/retry eksplisit | preparing → retrieving → waiting → writing → done |
| 15s belum ada raw token | slow di state UI; request masih berjalan |
| Retrieval/rewrite/embedding/selector total 3 menit | failed + timeout; cancel, tanpa retry |
| 30s setelah prepare tanpa raw token | failed + timeout |
| 20s stall setelah raw token | cut + timeout, flush raw partial |
| HTTP/network/invalid output | failed sebelum raw, cut setelah raw; error dipertahankan |
| Stop/back/switch/new/delete/background | cancel segera, flush stopped sebelum perpindahan |
| Proses restart | interrupted dari repository; tidak resend |
| Owner/attempt hilang atau callback false | interrupted/discard; tidak menjadi not_found |
| Revision berubah/buku dihapus | cancel, archive/readOnly atau state buku hilang |

Raw JSON dari #117 hanya untuk checkpoint. #141 mengirim proyeksi terstruktur
`frame.preview`, dipagari attempt dan diperbarui maksimal20Hz. Objek paragraf
lengkap baru boleh memiliki chip sumber setelah validasi frozen + live sources;
preview tetap provisional dan sitasinya dicabut saat gagal/terputus. Hanya final frame yang
tervalidasi diteruskan ke finalize done. Clock memakai 15/30/20s yang sama dengan
Artinya; retrieval memakai deadline total3menit terpisah karena dapat mencakup
indexing buku. Nilai ini batas produksi konservatif, bukan hasil benchmark device.
Tidak memakai Pacer untuk menampilkan JSON yang belum tervalidasi.

Perpindahan sesi diserialkan dan menutup satu run sebelum aksi berikutnya; send
nonaktif selama perpindahan. Scroll anchor stabil ditahan di memori dan disimpan
saat stop/perpindahan. Callback stream baca lama ditolak memakai generation seleksi;
cleanup subscription tidak menghambat navigasi. Retry hanya turn terakhir yang
cut/failed/stopped/interrupted, menimpa attempt tanpa menambah pertanyaan user.

`AppLifecycleListener` memanggil stop pada inactive/hidden/paused/detached; resumed
tidak mengirim ulang. Back/route change di #120/#121 **harus await `stop()` sebelum
navigasi**. Dispose juga cancel/flush melalui instance repository asal, dan semua
callback lama dipagari lifetime. Dispose Riverpod bersifat sinkron: flush fallback
berjalan async. `ChatLifecycle` (#119) menyimpan callback stop setiap lifetime
controller sampai flush dispose selesai, termasuk layar tertutup/paused. Restore
memanggil `close()` sebelum SQLite ditutup: blok send/retry, await stop seluruh
controller, lalu dispose repository + retrieval asal. Flush gagal membatalkan
restore; callback asal tidak dapat menulis ke DB baru meski ID backup sama.
Restore/provider rebuild memasang lifetime baru; callback lama tidak membaca ref/
state/instance provider baru. Tidak ada key di ChatState.

Import Markdown memakai `ChatLifecycle.changeContent` untuk blok send/retry buku
itu + await stop sebelum transaksi isi/revision; buku lain tetap dapat berjalan.
Invalidasi `appDatabaseProvider` setelah restore (sukses/gagal) membangun ulang
repository, retrieval, lifecycle, ViewModel dan seleksi sesi dari DB yang dibuka.
Index in-memory memakai bookId+revision+manifest, sehingga append/reorder atau
replace panjang sama tetap reindex pada send berikutnya. Jika isi
sudah berubah sebelum cancel/flush, guard repository menolak late write; arsip tetap
readOnly. Jangan melemahkan guard untuk memfinalisasi ke revision lain.

### Percakapan natural (#137)

Chat tetap memakai repository/ViewModel/provider/renderer yang sama. Domain
ChatAnswer menyimpan formatVersion dan setiap ChatAnswerBlock memiliki kind; UI
merender teks dan sumber yang tersedia, tanpa cabang format layar baru. V2 tidak
memakai fixed note partial/not_found v1. Completed partial/clarify/off_topic dan
legacy no-source menjadi konteks dialog, bukan bukti buku. Raw checkpoint tetap
bukan teks UI. No-source tidak memotong stream sebelum model dapat menjawab atau
meminta klarifikasi; validation owner/attempt/revision/sources dan cancellation
sebelum/sesudah network tetap berjalan.

### Penelusuran adaptif (#138)

`chat_exploration.dart` mengatur window global, catatan/range bersumber, manifest
dan checkpoint policy1. `ChatContextRepository.prepare` memperluas rewrite existing,
menjalankan pencarian berbatas atau scan batch urut, lalu freeze sumber lewat
ChatRepository seperti sebelumnya. Catatan tidak dipakai sebagai kutipan asli.
`ChatRepository` menyimpan progres dalam kolom exploration schema10, dengan guard
attempt/revision/dispose yang sama. `continueExploration` membuat turn baru;
ViewModel memasang guard sebelum await sehingga double-tap tidak menggandakan run.
UI memakai status/progress dan Stop existing, serta Lanjutkan saat ada checkpoint
terminal belum selesai. Tidak ada request saat rebuild/hydrate/resume/settings.
Budget dan batas sintesis ada di [llm.md](llm.md). Source visit tetap #122.

### Preview jawaban (#141)

`chat_preview.dart` memiliki reader incremental dengan batas48KB/32blok/depth32,
penanganan escape/surrogate dan duplicate-key guard; validator blok dipakai ulang
oleh parse final. `ChatTurn.preview` adalah proyeksi baca dari raw checkpoint,
bukan kolom DB. `ChatState.preview` berisi attemptRef+blok runtime; timer50ms
terpisah dari timer timeout dan dibatalkan saat terminal/dispose. Finalize yang
ditolak tidak mempertahankan sitasi. Renderer memakai anchor/SelectableText sama,
cache turn lain selama delta, dan live-region hanya untuk status.

### Intip dan kunjungan sumber (#122)

`ChatSourceChip` membuka `ChatSourceSheet` lokal (pola A5), lalu
`Routes.chatSource(ChatSourceRef)` di bawah route chat:
`/reader/:bookId/chat/source/:sessionId/:turnId/:attempt/:sourceId`.
URL hanya ID; `ChatRepository.resolveSource/watchSource` memeriksa kepemilikan,
attempt, sumber frozen yang benar-benar disitasi, revision, chapter.id, range,
snapshot dan hash terhadap teks saat ini dalam transaksi baca. Sumber provisional
harus sudah menjadi blok lengkap pada checkpoint; sumber final hanya dari jawaban
trusted. Sumber gagal/arsip berubah tetap dapat diintip sebagai snapshot, tanpa jump.
Resolver tidak menjalankan recovery/markOpened, indexing, atau request AI.

`ChatSourceVisitView` memantau pencabutan sumber dan pergantian repository saat
restore, termasuk ID yang dipakai ulang. Renderer `ReaderView(sourceVisit: ...)`
yang sama dipakai: `_save`, `_flushReading`, markOpened/markFinished, interaksi jam
baca, debounce, lifecycle dan dispose tidak mencatat aktivitas kunjungan. TOC/next
hanya mengubah tampilan lokal. Tap Artinya dan entry chat tidak aktif di mode ini.
Range UTF-16 disorot dengan token Stabilo; posisi awal mengikuti kotak teks range,
dan kutipan panjang disejajarkan di bawah kapsul atas. Aa tetap memakai preferensi
reader; identity sumber tidak berasal dari nomor urut bab.

Reader utama tetap mounted dan jam bacanya paused lewat `_pushOffReader` selama
chat/visit. Intip/visit menahan auto-follow history supaya delta tidak menggeser
posisi chat yang ditinggal. Balik ke obrolan mem-pop visit; Lanjut baca semula
mengembalikan `ReaderReturn.reading` melalui chat dan overlay Artinya/Bedahin ke
reader asli beserta posisi yang dicapture saat masuk. Tidak ada adopsi posisi sumber
menjadi progres baru. Revisi pacing/no-auto-scroll menyeluruh tetap di #123.
