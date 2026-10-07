# Arsitektur & Alur

## Routing (go_router)

- `/` → Rak buku
- `/reader/:bookId` → Halaman baca (posisi dari `reading_progress`)
- `/settings` → Pengaturan (termasuk bagian Backup & restore)
- Bottom sheet artinya, Aa, dan Daftar isi **bukan route**, cukup `showModalBottomSheet`.

## Provider utama (Riverpod)

- `booksStreamProvider` → `StreamProvider` dari query Drift, untuk grid rak.
- `chapterParagraphsProvider(chapterId)` → paragraf satu chapter dari Drift.
- `bookChaptersProvider(bookId)` → daftar chapter terurut `sortOrder` (untuk Daftar isi).
- `groupAiProvider(GroupRef)` → `FutureProvider.autoDispose.family`:
  1. Cek `ai_results`
  2. Kalau belum ada: ambil paragraf grup + sampe 3 paragraf (bukan heading/pemisah) sebelum paragraf pertama grup di chapter yang sama sebagai konteks
  3. Panggil LLM (API key dibaca dari Keychain, model dari `ai.model`)
  4. Validasi jumlah `translations` = jumlah paragraf grup
  5. Simpan ke Drift, return hasil

  **Auto-retry Riverpod 3 dimatiin** (`retry: (_, _) => null`): tiap percobaan motong saldo. Gagal → `AsyncError` berisi `AiException`, dicoba ulang cuma lewat `ref.invalidate` (tombol "Coba lagi"). Hasil tetep disimpen walaupun sheet keburu ditutup. Dua tap ke grup yang sama pas lagi loading = satu request.
- `groupAiStreamProvider(GroupRef)` → `NotifierProvider.autoDispose.family` (`GroupAiStream`), versi streaming yang dipakai sheet Artinya. State `AiStream`: `phase` (`AiPhase`), `draft` (teks yang udah dateng, belum di-pacing), `sources` (panjang paragraf asli buat placeholder), `error`, `cached`.
  1. Cache dulu → langsung `done` (`cached`), gak manggil LLM.
  2. Belum ada → stream jawaban bersection ([llm.md](llm.md)), state `waiting` → `translating` → `meaning` → `done`; cabang `slow` (15 detik tanpa token, request tetep jalan; token masuk → `translating`), `failed` (30 detik tanpa token = `timeout`, gak ada key, HTTP, dll), `cut` (putus, atau token berhenti 20 detik di tengah; teks yang udah masuk tetep di `draft`).
  3. Lengkap → validasi; gak valid → sekali lagi lewat jalur JSON tanpa streaming (`explain(attempts: 1)`). Disimpen cuma kalau lengkap dan valid.
  4. **Beda sama `groupAiProvider`:** ke-dispose (tutup sheet, Lanjut ke grup lain) = request dibatalin (`CancelToken`) dan gak ada yang disimpen; ngulang satu grup cuma pecahan sen. Dua tap ke grup yang sama tetep satu request (family). Coba lagi = `ref.invalidate`, mulai lagi dari `waiting`. Kalau pas dogfooding sering kebuka-tutup gak sengaja: tambah masa tenggang (request jalan 2–3 detik abis sheet ditutup).
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
- **Akhir bab**: kartu akhir bab keliatan → dua kapsul muncul, kapsul bawah nulis "Bab N beres". **Akhir buku**: layar sendiri tanpa kapsul, garis progres penuh 100%, cover pake cover default (tanpa bulatan huruf), status bar balik.
- **Lanjut baca** (buka buku yang ada posisi tersimpannya): kapsul muncul 2,5 detik buat orientasi terus ngumpet sendiri (batal kalau user udah scroll duluan). Grup tempat posisi tersimpan dikasih kilatan stabilo sekali, 0 → 60% → 0 dalam 1,2 detik. "Kurangi gerakan" iOS nyala → tanpa kilatan, gantinya garis kiri 4pt yang ilang setelah 3 detik.
- Status bar iOS ngumpet bareng kapsul kalau toggle "Sembunyiin jam & baterai" nyala (default nyala; togglenya di Aa, #18). Keluar halaman baca → status bar balik.

## Persentase baca

`(chapters.charOffset + jumlah karakter paragraf sebelum posisi) / books.totalChars`.

Buku Markdown yang chapternya belum lengkap (nanti, [import-formats.md](ideas/import-formats.md)) tidak punya total yang pasti, jadi tampilkan progres per chapter saja.

## Gotcha iOS

- **Jangan simpan absolute path di database.** Path container app iOS bisa berubah setiap update/reinstall. Simpan nama file, gabungkan dengan `getApplicationDocumentsDirectory()` saat runtime.
- File dari picker biasanya ada di folder sementara, jadi wajib di-copy ke Documents.
- Buat folder `books/` dan `covers/` saat app start (`create(recursive: true)`).
