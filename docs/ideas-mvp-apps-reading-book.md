# Luma: EPUB Reader + Terjemahan & Makna per Paragraf

> Nama app: **Luma**
> Desain: **Stabilo** (lihat bagian 5)
> Status: siap eksekusi MVP
> Terakhir diupdate: Oktober 2026

> **Untuk Claude Code:** file ini adalah sumber kebenaran untuk keputusan produk, data model, dan alur. Ikuti struktur di bagian 6–10. Bagian 12 ke bawah adalah rencana iterasi berikutnya dan ide kasar, **jangan dikerjakan** kecuali diminta.

---

## 1. Latar Belakang

Alur baca saat ini:

1. Download ebook EPUB
2. Buka di app Books (iPhone)
3. Select paragraf, copy
4. Pindah ke Gemini, paste, ketik pertanyaan terjemahan + makna
5. Baca jawaban, balik ke Books, cari lagi posisi terakhir

Masalah utamanya bukan kualitas terjemahan, tapi **friksi bolak-balik antar app** yang memutus fokus baca tiap beberapa menit.

## 2. Tujuan

Mengubah alur di atas menjadi **satu tap**: tap paragraf → langsung muncul terjemahan Indonesia + penjelasan makna, tanpa keluar dari halaman baca dan tanpa ngetik prompt.

### Patokan sukses MVP

- Terasa **lebih cepat dan nyaman** daripada alur Books + copy-paste ke Gemini.
- Dipakai sendiri (dogfooding) untuk baca minimal satu buku sampai selesai.

---

## 3. Fitur MVP

| # | Fitur | Keterangan |
|---|-------|-----------|
| 1 | Import EPUB | Tombol import via `file_picker`. File di-copy ke penyimpanan app, lalu **diparse sekali** ke format internal (chapter → paragraf → grup). |
| 2 | Rak buku | Grid buku dengan cover (atau cover default), judul, progres. Kartu "Lanjut baca yuk" untuk buku terakhir. Urut terakhir dibuka. |
| 3 | Halaman baca | Teks per paragraf, nyaman dibaca lama. Pengaturan Aa (font, ukuran, jarak baris, tema). |
| 4 | Daftar isi | Pindah antar chapter dari halaman baca. |
| 5 | Tap → terjemahan + makna | Tap paragraf mana pun → **seluruh grup paragrafnya** distabilo dan dikirim ke LLM. Bottom sheet: terjemahan per paragraf + satu penjelasan makna. Ada state loading, hasil, error. |
| 6 | Cache hasil AI | Disimpan di Drift per grup. Grup yang sudah pernah di-tap tidak memanggil LLM lagi. |
| 7 | Simpan posisi baca | Saat buku dibuka lagi, langsung lanjut ke posisi terakhir. |
| 8 | Pengaturan | API key OpenRouter, model ID, hapus cache. |
| 9 | Backup & restore | Export semua data (buku, terjemahan, posisi baca, pengaturan) ke satu file `.zip`, simpan ke Files/AirDrop. Restore dari file itu. Pengingat kalau sudah lama belum backup. Detail di bagian 10. |

### Di luar scope MVP (iterasi berikutnya)

- **Recap bacaan**: terjemahan + makna semua yang sudah dibaca, plus overview "sejauh ini" → **Iterasi 2, lihat bagian 12**
- Import **Luma Markdown** (hasil foto buku fisik, dikonversi di luar app) + support PDF & format lain → **ide kasar, lihat bagian 13**
- "Open in" dari app Files / share sheet iOS
- Backend proxy untuk API key (wajib kalau app dirilis ke orang lain)
- Highlight, catatan, bookmark
- Pilihan mode penjelasan (ringkas / detail / istilah sulit)
- Sinkronisasi antar device

---

## 4. Tech Stack

Mengikuti stack Mibu supaya pola dan boilerplate bisa dipakai ulang.

| Kebutuhan | Package |
|-----------|---------|
| State management | `flutter_riverpod` |
| Database lokal | `drift` |
| Routing | `go_router` |
| Parsing EPUB | parser sendiri (`archive` + `xml`), lihat catatan di bawah |
| Parsing HTML chapter | `html` (DOM parser) |
| Pilih file | `file_picker` |
| Path penyimpanan | `path_provider`, `path` |
| Hash file (anti-duplikat) | `crypto` |
| HTTP ke LLM | `dio` atau `http` |
| Simpan API key | `flutter_secure_storage` |
| Value object | `freezed` |
| Zip backup | `archive` |
| Bagikan/simpan file backup | `share_plus` |

> Cek tanggal update terakhir dan issue tiap package di pub.dev sebelum dipakai, terutama package EPUB.
>
> **Parser EPUB ditulis sendiri** (Okt 2026): `epubx` terakhir rilis Juni 2023, gagal total kalau TOC gak standar, dan nahan `archive` di 3.x. Parser sendiri cuma butuh container → OPF → spine → TOC (nav EPUB3 / NCX EPUB2) → cover, dan entri TOC yang rusak dilewatin, bukan bikin import gagal.
>
> Teks bacaan dirender dari tabel `paragraphs` (teks polos), bukan dari HTML mentah EPUB, jadi package render HTML tidak dibutuhkan untuk MVP.

---

## 5. Desain: Stabilo

Referensi lengkap (layar, komponen, token): https://claude.ai/artifact/EBwv9zJBLZQJa5WWYiaJ7F

### Prinsip

1. **Teks dulu, UI belakangan.** Halaman baca bersih. UI muncul hanya saat dibutuhkan (sheet artinya, Aa, progres tipis di bawah).
2. **Kuning = yang lagi penting.** Stabilo hanya untuk aksi utama dan paragraf/grup yang sedang di-tap. Satu layar, satu tombol kuning.
3. **Malem tetep adem.** Mode gelap pakai hitam hangat, bukan hitam pekat.

### Font

| Font | Dipakai untuk |
|------|---------------|
| Bricolage Grotesque | UI, judul, label, tombol |
| Atkinson Hyperlegible | Teks bacaan + isi sheet (default, opsi "Jelas") |
| Literata | Opsi bacaan "Kayak buku" |
| Font sistem iOS | Opsi bacaan "Bawaan iOS" |

Bundle font sebagai asset (jangan fetch runtime).

### Token warna utama

| Token | Terang | Gelap |
|-------|--------|-------|
| canvas | `#FFFBEF` | `#22201C` |
| sheet | `#FFFDF6` | `#2C2A25` |
| muted | `#F2EDDD` | `#36332D` |
| ink | `#1C1C1C` | `#DDD7C8` |
| ink2 | `#5E5A4E` | `#A19B8E` |
| accent (stabilo) | `#FFD84D` | `#E9C75A` |
| pink | `#FFC2D3` | `#D99BAE` |

Implementasi Flutter: `ThemeExtension` (`StabiloColors`) dengan satu set terang dan satu set gelap. Detail token lain (track, outline, scrim, highlight) ada di artifact.

### Halaman baca imersif (ReaderCapsule)

Pas baca, layar isinya cuma teks + garis progres tipis. Menu nongol sebagai dua kapsul ngambang kalau dibutuhin. Top bar 60pt cuma buat Rak & Pengaturan. Spek lengkap di board "Baca imersif · ReaderCapsule" (+ layar 03 Baca, 03b imersif, 03c Lanjut baca).

- **Kapsul atas**: tinggi 58, radius penuh, 6pt di bawah safe area atas, kiri-kanan 24. Isi: balik · judul + "Bab N · judul bab" · daftar isi · Aa. Tombol 44 bulet muted; tombol yang sheet-nya lagi kebuka (Daftar isi / Aa) jadi kuning.
- **Kapsul bawah**: tinggi 40, 14pt di atas safe area bawah, di tengah. Persen + bar 88 + "±N mnt lagi" (atau "Bab N beres"). Cuma info.
- **Gaya kapsul**: latar sheet. Terang: garis 1,5 ink + bayangan tekan 2 + bayangan lembut. Gelap: garis `#46423A` + bayangan lembut.
- Teks yang lewat di belakang kapsul dimudarin pake **EdgeFade** (lihat di bawah), bukan gradien warna latar.
- **Garis progres** 2pt selebar layar, tepat di atas safe area bawah (gak kepotong sudut layar, gak numpuk home indicator). Terang `#E6B800`, gelap `#E9C75A`, track ink 8–10%. Progres per buku; 100% di layar akhir buku.
- Kapsul itu **overlay**: teks gak loncat pas kapsul muncul/ngumpet. Teks awal bab mulai 86pt di bawah safe area atas (board: 140) biar judul bab gak ketutup.

### EdgeFade (tepi area scroll)

Board "EdgeFade · tepi area scroll". Tepi area scroll mudar halus pake **mask** (`ShaderMask` + `BlendMode.dstIn`, widget `EdgeFadeScroll`): isinya yang transparan, bukan gradien warna latar, jadi aman di terang & gelap. Dipasang di tepi area scroll yang ketemu elemen nempel (judul/header, tombol aksi, kapsul). Fade atas cuma muncul kalau udah di-scroll; fade bawah cuma ada di atas tombol aksi / kapsul bawah, dan cuma kalau masih ada isi di bawah. Muncul/ilang 150 ms.

**Tepi bawah edge-to-edge.** Tepi bawah layar & sheet gak pernah dipudarin: isi digambar tembus sampe tepi fisik, lewat di bawah home indicator. Area scroll gak dibungkus `SafeArea(bottom: true)`; padding bawah scroll = safe area (`MediaQuery.paddingOf(context).bottom`, 34pt) di dalam scroll, jadi item terakhir bisa naik ke atas home indicator dan tetep bisa di-tap. Tombol & elemen nempel tetep di dalam safe area.

| Tempat | Fade atas | Fade bawah | Catatan |
|--------|-----------|------------|---------|
| Sheet tanpa tombol aksi (Aa, Daftar isi, `SheetFrame` tanpa tombol) | 20pt di bawah judul | – (mentok ke tepi) | Padding bawah sheet 0, item terakhir padding = safe area |
| Sheet + tombol aksi (`SheetFrame` bertombol, Ringkasan pulihin) | 20pt di bawah judul | 20pt di atas tombol | Tombol di atas safe area 34 |
| Sheet Artinya | 20pt di bawah header; header ngumpet = 20pt di bawah grabber (dari y 12) | 20pt di atas tombol, cuma selama tombol keliatan; tombol ngumpet = edge-to-edge, tanpa fade | Fade ikut animasi header & tombol (200ms) |
| Layar penuh (Rak, Pengaturan) | 20pt di bawah header yang nempel | – (mentok ke tepi) | Rak: header + "Semua buku" nempel, tanpa garis pemisah. Pengaturan: balik + judul nempel |
| Baca · kapsul keliatan | 48pt dari tepi kapsul | 48pt ke tepi kapsul, sisa ±18% terus sampe tepi layar | Status bar kosong; gak ada pita kosong di bawah garis progres. Awal bab gak ada fade atas |
| Baca · imersif | – | – (mentok ke tepi) | Teks lewat di bawah garis progres sampe tepi |

Layar baca: kekuatan mask ngikutin `ReaderChrome.hidden` (controller kapsul yang sama, 200 ms ease-out). Kapsul geser keluar → sisa 18% naik ke 100%, status bar yang kosong keisi, jadi teks gak kedip atau loncat; kapsul masuk lagi → kebalikannya. Menu tekan lama & urutkan cuma 2–3 item, gak pernah scroll, jadi belum dipasang.

### Pengaturan Aa

Sheet "Atur bacaan lo" (board 07), dibuka dari tombol Aa di kapsul. Tiap pilihan langsung disimpen dan langsung keliatan di teks; scrim-nya tipis (8% terang, 18% gelap) biar teks di belakang jadi preview. Posisi baca nempel: titik yang lagi di garis atas tetep di situ pas ukuran/font/jarak/margin diganti.

- Ukuran huruf: 7 step 16 · 17 · 18 · **18,5** · 20 · 22 · 24 (tombol A kecil / A gede)
- Font: **Jelas** (Atkinson Hyperlegible) / Kayak buku (Literata, jarak baris +0,05) / Bawaan iOS (SF)
- Jarak baris: Rapat 1,5 / **Pas 1,65** / Lega 1,85; mode gelap +0,05
- Margin teks: Sempit 16 / **Pas 24** / Lega 32. Area tap margin minimal 24pt: di Sempit, 8pt pinggir kolom ikut diitung area kosong
- Tema: Terang / Gelap / **Ikut iOS** → `themeMode` app
- Tampilan layar: "Sembunyiin jam & baterai" (**nyala**) dan "Tampilin garis progres" (**nyala**), pake Switch dari board Komponen dasar (51 × 31)
- Disimpen per perangkat (bukan per buku) di tabel `settings`, ikut backup. Nilai yang gak dikenal (backup rusak) balik ke default

### Sheet Artinya: ikut Aa, header & tombol ngumpet pas scroll

Board "Spek · Artinya ngumpet pas scroll" dan "Terpilih · Artinya ngumpet pas scroll · Opsi A (geser ngikut)": area baca nambah 54% (335 → 516pt di sheet 528).

- **Teks ikut Aa:** terjemahan dan blok makna pakai font, ukuran, jarak baris, dan margin yang sama dengan halaman baca (`ReaderTypography`, satu sumber buat dua-duanya). Padding dasar sheet (24) jadi batas bawah margin: Sempit (16) sama kayak Pas, Lega (32) nambah 8 di kiri-kanan isi. Judul, chip, tombol, toast, dan teks pesan error / API key kosong tetap ukuran UI. Placeholder loading pakai tinggi baris yang sama. Ganti Aa langsung kebawa (provider yang sama).
- **Struktur:** sheet 528 (62,5% layar, `DraggableScrollableSheet`, semua state). Isi scroll setinggi sheet, padding atas 91 / bawah 102 (tombol 52 + jarak 16 + safe area 34). Header (judul + X), grabber, dan Salin / Lanjut lapisan di atas isi, jadi ngilangnya header gak geser teks.
- **Ngumpet (cuma scroll dari jari; scroll programatik gak ngitung):** header ikut isi 1:1 pas turun dan ilang setelah 91pt; naik ≥ 12pt → turun lagi ngikutin jari dari atas, dilepas di tengah snap ke yang terdekat. Salin / Lanjut geser keluar setelah turun ≥ 24pt (200ms, ease-out), balik pas naik ≥ 12pt atau mentok bawah. Header tetap ngumpet sampai scroll naik; balik ke paling atas = semua lengkap. Ambang (24 / 12) dari `ScrollRun`, dipakai bareng kapsul baca.
- **Gak pernah ngumpet:** isi muat semua, state loading / error / API key kosong, VoiceOver nyala. Kurangi gerakan: gak geser, gak ngikutin jari, fade 150ms.
- **Nutup:** swipe turun di grabber (ngikutin jari, nutup kalau di-fling atau ditarik jauh, pas offset berapa pun), swipe turun di isi pas offset 0, atau tap area kosong di atas sheet (bukan munculin kapsul baca).
- **Tinggi area baca yang keliatan** (`MeaningChrome.readHeight`): tinggi sheet dikurangi chrome yang keliatan, buat highlight sinkron (#35).

### Sheet Artinya: streaming

Board "Terpilih · Artinya streaming · Opsi B · muncul halus (diperbaiki)" dan "Artinya streaming · perilaku". Sumbernya `groupAiStreamProvider` (bagian 8). Grup yang udah ke-cache langsung tampil jadi, tanpa ritme dan tanpa ikut turun. Satu widget buat semua tahap (`_Answer`), jadi pas selesai gak ada loncatan layout dan posisi scroll gak di-reset. Tinggi sheet tetap 528 di semua tahap.

- **Tahap:** nunggu (header "Bentar, lagi mikir...", placeholder per paragraf + makna) → nulis terjemahan (paragraf masuk berurutan, sisanya placeholder) → nulis makna → selesai (header "Artinya gini nih", Salin aktif). Header cuma judul + X, tanpa chip.
- **Kelamaan** (15 detik tanpa token): kartu "Agak lama nih..." di atas isi (Batal / Coba lagi). Token masuk → kartunya ilang sendiri. **Kepotong**: teks yang udah masuk tetep, placeholder dibuang, banner pink "Yah, kepotong di tengah" + Coba lagi (mulai dari awal).
- **Ritme:** huruf keluar per frame ngikutin `Pacer` (bagian 9). **Deviasi dari board (2):** aturan adaptif, bukan maks 2× baseline (data spike #34).
- **Ujung teks:** gak ada kursor, kedip, atau kuning di teks. 4 kata terakhir bagian yang lagi ditulis opasitas 80 · 60 · 42 · 26%, diem (`Text.rich`); selesai → solid dalam 300 ms. **Deviasi dari board (1):** tanpa fade-in 150 ms per potongan, karena teks keluar per huruf dan dua efek itu numpuk.
- **Tombol:** Salin / Lanjut dikunci keliatan selama belum selesai. Salin nonaktif; statusnya di tombol itu: tiga titik 4pt berdenyut (opasitas 30 ↔ 85%, 1,6 detik) + "Lagi mikir" / "Lagi nulis", ink2 di atas muted. Selesai → crossfade 150 ms ke "Salin". Kelamaan / kepotong: "Salin" abu, statusnya di kartu / banner. Lanjut mati selama masih diproses (nunggu, kelamaan, nulis), aktif lagi pas selesai atau kepotong (deviasi dari board, yang Lanjut-nya selalu aktif). Batalin di tengah = X ("Batalin" di VoiceOver), tutup sheet = request dibatalin.
- **Gak bisa di-scroll sebelum teks pertama masuk** (nunggu / kelamaan): isinya cuma placeholder. Nutup lewat X, grabber, atau tap di atas sheet (swipe di isi gak nutup di tahap ini).
- **Gak ikut turun (deviasi dari board, Okt 2026):** isi gak di-scroll otomatis. Sheet diem di awal terjemahan biar bisa dibaca dari paragraf pertama sementara sisanya ditulis di bawah; scroll cuma dari jari. Gak ada tombol "Ke bawah". Header ikut isi 1:1 pas di-scroll selama streaming (kayak bagian dari isi), tombol gak ngumpet; abis selesai, aturan ngumpet biasa nerusin dari posisi header terakhir.
- **Placeholder ikut Aa:** baris = ⌈huruf × lebar huruf rata-rata ÷ lebar kolom⌉, huruf = panjang paragraf asli × 1,05 (makna 130). Lebar huruf rata-rata diukur pakai `TextPainter` dari font + ukuran Aa yang aktif (bukan konstanta per font). Tinggi baris = baris teks. Isi tumbuh ke bawah.
- **Kurangi gerakan:** teks muncul per bagian utuh (satu paragraf, lalu makna), tanpa pudar, titik diem, placeholder tanpa shimmer.
- **VoiceOver:** sheet berlabel "Artinya, lagi ditulis"; bagian yang lagi ditulis gak dibacain sampai utuh; selesai → diumumin "Artinya udah lengkap".

### Copy

Bahasa Indonesia gaya Gen Z, santai. Contoh: "Rak buku lo", "Lanjut baca yuk", "Artinya gini nih", "Maksud penulisnya tuh...", "Bentar, lagi mikir...", "Yah, gagal nih".

### Layar yang sudah didesain

Semua layar MVP awal sudah final (terang + gelap): rak kosong/berisi, baca, artinya (loading / hasil / error / udah disalin / API key kosong) dengan highlight grup, Aa, daftar isi, akhir bab, akhir buku, import (proses / berhasil / duplikat / rusak / bukan EPUB / DRM), urutkan rak, tekan lama buku, info buku, konfirmasi hapus, pengaturan, penanda grup yang sudah diterjemahkan.

### Layar yang masih didesain

Backup & restore (bagian 10): bagian Backup di Pengaturan, proses export, restore (pilih file → ringkasan → konfirmasi → proses → berhasil / gagal), banner pengingat backup.

---

## 6. Data Model (Drift)

Prinsip: **file diparse sekali saat import** ke format internal. Reader, AI, dan Recap hanya membaca tabel di bawah, tidak pernah parse file ulang.

> **Keputusan penting: ID chapter stabil.** Chapter bisa masuk tidak berurutan (mis. import Markdown chapter 3, lalu 7, lalu 5; lihat bagian 13). Karena itu semua tabel lain menunjuk ke `chapters.id` (stabil), **bukan** ke posisi/urutan chapter. Urutan tampil diatur kolom `sortOrder`.

### `books`

| Kolom | Tipe | Catatan |
|-------|------|---------|
| id | int (PK) | |
| sourceType | text | `epub` (MVP) / `markdown` (nanti) |
| bookKey | text? (unique) | Slug untuk mencocokkan import Markdown ke buku yang sama (mis. `atomic-habits`). Null untuk EPUB |
| title | text | |
| author | text? | |
| fileName | text? | **Nama file saja**, bukan absolute path. Null untuk buku Markdown |
| coverName | text? | Nama file cover. Null → pakai cover default |
| hash | text? (unique) | SHA-256 isi file EPUB, untuk cegah import dobel |
| parserVersion | int | Versi logika parsing + grouping. Naik → re-import & invalidasi cache buku itu |
| totalChars | int | Untuk hitung persentase baca (hanya bermakna untuk buku lengkap) |
| createdAt | datetime | |
| lastOpenedAt | datetime? | Untuk urutan rak |
| firstOpenedAt | datetime? | Pertama kali dibuka. Diisi sekali, gak berubah lagi |
| readingSeconds | int (default 0) | Total waktu baca aktif, ditampilkan di layar akhir buku ("6 jam 20 mnt", atau "45 mnt" di bawah 1 jam). Tetap dipertahankan walau ada `reading_sessions` (ditulis satu transaksi sama sesinya) |
| finishedAt | datetime? | Pertama kali layar akhir buku kebuka. Diisi sekali, gak ditimpa. Sengaja gak disimpulin dari sesi: lompat ke bab terakhir bisa ngelabuin |

**Waktu baca aktif** dihitung selama halaman baca kebuka dan app di foreground. Berhenti kalau 2 menit gak ada scroll/tap (2 menit itu ikut dihitung), lanjut lagi pas ada interaksi. Disimpan bertahap (tiap scroll berhenti, pindah bab, app ke background, keluar halaman baca), jadi app yang dimatiin iOS cuma kehilangan beberapa detik terakhir.

### `chapters`

| Kolom | Tipe | Catatan |
|-------|------|---------|
| id | int (PK, autoincrement) | **Kunci stabil**, dipakai tabel lain |
| bookId | int (FK) | |
| sortOrder | int | Urutan tampil. EPUB: urutan TOC. Markdown: dari nomor chapter |
| chapterNumber | int? | Nomor bab asli dari buku (untuk Markdown / daftar isi) |
| title | text | Dari TOC/nav EPUB, fallback "Bab N" |
| charOffset | int | Jumlah karakter sebelum chapter ini (untuk persentase). Dihitung ulang kalau ada chapter disisipkan |

Index: `(bookId, sortOrder)`.

### `paragraphs`

| Kolom | Tipe | Catatan |
|-------|------|---------|
| chapterId | int (FK → chapters.id) | |
| paragraphIndex | int | Urutan dalam chapter |
| groupIndex | int? | Grup untuk tap/AI. Null untuk heading & pemisah adegan (tidak bisa di-tap) |
| type | text | `paragraph` / `heading` / `scene_break` |
| text | text | Teks polos yang sudah dinormalisasi |

Unique key: `(chapterId, paragraphIndex)`. Index tambahan: `(chapterId, groupIndex)`.

### `reading_progress`

| Kolom | Tipe | Catatan |
|-------|------|---------|
| bookId | int (PK) | |
| chapterId | int (FK) | |
| paragraphIndex | int | Paragraf paling atas yang keliatan di bawah safe area atas |
| paragraphOffset | real (default 0.0) | Bagian paragraf itu yang udah lewat garis atas, **fraksi tinggi paragraf** 0.0–1.0 (bukan piksel, biar tetep pas kalau font/ukuran/jarak baris diganti di Aa). Di-clamp 0–1 pas nyimpen dan pas baca |
| updatedAt | datetime | |

### `ai_results`

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

### `reading_sessions`

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

### `ai_calls`

Log append-only request LLM, terpisah dari cache `ai_results` (`createdAt`-nya ke-reset tiap retranslate, barisnya ikut kehapus pas re-import). Dasar statistik biaya, bantuan AI per 1.000 karakter, dan bab tersulit. Cache hit gak nulis baris. Pengisiannya di #47 (ditunda, Okt 2026: statistik AI jadi raw idea, tabelnya kosong dulu).

| Kolom | Tipe | Catatan |
|-------|------|---------|
| id | int (PK, autoincrement) | |
| bookId | int? (FK → books.id, set null) | `set null` supaya biaya bulanan gak berubah waktu buku dihapus |
| chapterId | int? (FK → chapters.id, set null) | |
| groupIndex | int? | |
| kind | text | `group` (terjemahan + makna). Recap (bagian 12) nanti nambah nilai |
| model | text | |
| promptVersion | int | |
| chars | int | Panjang teks target, penyebut "per 1.000 karakter" |
| promptTokens, completionTokens | int? | Null = model gak ngirim `usage` |
| costUsd | real? | Dari `usage` OpenRouter. Null = gak tercatat (tampilin "gak tercatat", bukan 0) |
| firstTokenMs, totalMs | int? | Latensi |
| error | text? | `AiError.name`. Null = sukses |
| createdAt | datetime | |

> ⚠️ **Indeks paragraf dan grup harus stabil.** Logika parsing dan grouping jangan diubah sembarangan setelah ada data. Kalau harus berubah, naikkan `parserVersion`, re-import buku, dan hapus `ai_results` buku tersebut.

### Versi schema & migrasi

| Versi | Perubahan |
|-------|-----------|
| 1 | Awal |
| 2 | `books.firstOpenedAt`, `books.readingSeconds` |
| 3 | `reading_progress.paragraphOffset` |
| 4 | `ai_results.promptVersion` (baris lama = 1, prompt sebelum #40) |
| 5 | Pencatatan statistik (#42): tabel `reading_sessions` + `ai_calls`, `books.finishedAt`, `ai_results.openCount` + `lastOpenedAt`. Tabel baru kosong, baris lama `openCount` = 0 |

Tiap ubah tabel: naikkan `schemaVersion`, tambah langkah di `onUpgrade`, dan test migrasi dari versi sebelumnya (data tetap utuh, schema hasil migrasi sama dengan install baru). Restore backup dari schema lama ikut dimigrasi saat database dibuka (bagian 10).

### Pengaturan

API key di `flutter_secure_storage`. Model ID, preferensi Aa, dan backup terakhir di tabel `settings` sederhana (key-value) di Drift, supaya ikut ter-backup. Model LLM: `ai.model` (model ID OpenRouter, default `z-ai/glm-5.3-flash`; pilihan dari daftar kandidat di bagian 9). API key di Keychain dengan kunci `openrouter_api_key`, cuma disimpen setelah lolos cek bentuk dan cek ke OpenRouter (bagian 9); kosong = dihapus. "Hapus cache" di Pengaturan = kosongin `ai_results` setelah konfirmasi; Pengaturan nampilin jumlah paragraf yang udah diterjemahin + ukuran teksnya. Backup terakhir: `backup.lastAt` (ISO 8601), `backup.lastName`, `backup.lastSize` (byte). Kunci Aa: `reader.size` (indeks step 0–6), `reader.font`, `reader.spacing`, `reader.margin`, `theme` (nama enum), `reader.hideStatusBar`, `reader.showProgressLine` (`true`/`false`). Urutan rak: `shelf.sort` (`lastOpened` / `title` / `added`, default `lastOpened`). Tampilan rak: `shelf.view` (`grid` / `list`, default `grid`). Hindari `shared_preferences` untuk data yang perlu ikut backup.

---

## 7. Logika Pengelompokan Paragraf

### Masalah

Satu `<p>` di EPUB = satu paragraf, sependek apa pun. Di bagian dialog, banyak paragraf cuma satu baris. Tap satu baris → loading → terjemahan satu baris terasa nanggung.

### Solusi

Paragraf pendek yang berurutan **digabung jadi satu grup saat import**, disimpan di kolom `groupIndex`. Tap paragraf mana pun di grup → seluruh grup distabilo → satu request LLM → hasil di-cache per grup.

Kenapa dihitung saat import, bukan saat tap: hasilnya **stabil**, cache selalu konsisten, dan Recap bisa memakai grup sebagai unit.

### Aturan (nilai awal, tuning saat dogfooding)

| Konstanta | Nilai | Arti |
|-----------|-------|------|
| `longThreshold` | 300 karakter | Paragraf ≥ ini berdiri sendiri sebagai satu grup |
| `targetChars` | 450 karakter | Grup ditutup setelah mencapai ukuran ini |
| `maxChars` | 800 karakter | Grup tidak boleh melewati ini |
| `maxParagraphs` | 6 | Maksimal paragraf per grup |

Aturan tambahan:

- Grup **selalu diputus** di heading, pemisah adegan (`***`, `* * *`, `<hr>`), dan batas chapter.
- Heading dan pemisah adegan **tidak punya grup** (`groupIndex = null`), tidak bisa di-tap.
- `groupIndex` unik per chapter, mulai dari 0.

### Pseudocode

```dart
List<int?> assignGroups(List<Paragraph> paras) {
  final result = List<int?>.filled(paras.length, null);
  final current = <int>[]; // index paragraf di grup berjalan
  var currentChars = 0;
  var groupIndex = 0;

  void flush() {
    if (current.isEmpty) return;
    for (final i in current) result[i] = groupIndex;
    groupIndex++;
    current.clear();
    currentChars = 0;
  }

  for (var i = 0; i < paras.length; i++) {
    final p = paras[i];

    if (p.type != ParagraphType.paragraph) {
      flush(); // heading / scene break: putus grup, tanpa groupIndex
      continue;
    }

    final len = p.text.length;

    if (len >= longThreshold) {
      flush();
      current.add(i);
      flush(); // paragraf panjang = grup sendiri
      continue;
    }

    if (current.isNotEmpty &&
        (currentChars + len > maxChars || current.length >= maxParagraphs)) {
      flush();
    }

    current.add(i);
    currentChars += len;

    if (currentChars >= targetChars) flush();
  }

  flush();
  return result;
}
```

Fungsi ini **pure** (tanpa I/O), jadi wajib dibuat unit test: dialog pendek beruntun, paragraf panjang tunggal, campuran, heading di tengah, batas `maxParagraphs`.

### Perilaku UI

- Tap paragraf → semua paragraf dengan `groupIndex` yang sama distabilo.
- Bottom sheet menampilkan terjemahan **per paragraf** (jeda baris tetap terlihat seperti dialog aslinya) + satu blok "Maksud penulisnya tuh...".
- Tombol "Paragraf berikutnya" → lompat ke **grup** berikutnya.

---

## 8. Arsitektur & Alur

### Routing (go_router)

- `/` → Rak buku
- `/reader/:bookId` → Halaman baca (posisi dari `reading_progress`)
- `/settings` → Pengaturan (termasuk bagian Backup & restore)
- Bottom sheet artinya, Aa, dan Daftar isi **bukan route**, cukup `showModalBottomSheet`.

### Provider utama (Riverpod)

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
  2. Belum ada → stream jawaban bersection (bagian 9), state `waiting` → `translating` → `meaning` → `done`; cabang `slow` (15 detik tanpa token, request tetep jalan; token masuk → `translating`), `failed` (30 detik tanpa token = `timeout`, gak ada key, HTTP, dll), `cut` (putus, atau token berhenti 20 detik di tengah; teks yang udah masuk tetep di `draft`).
  3. Lengkap → validasi; gak valid → sekali lagi lewat jalur JSON tanpa streaming (`explain(attempts: 1)`). Disimpen cuma kalau lengkap dan valid.
  4. **Beda sama `groupAiProvider`:** ke-dispose (tutup sheet, Lanjut ke grup lain) = request dibatalin (`CancelToken`) dan gak ada yang disimpen; ngulang satu grup cuma pecahan sen. Dua tap ke grup yang sama tetep satu request (family). Coba lagi = `ref.invalidate`, mulai lagi dari `waiting`. Kalau pas dogfooding sering kebuka-tutup gak sengaja: tambah masa tenggang (request jalan 2–3 detik abis sheet ditutup).
- `importControllerProvider` → `Notifier` untuk state import (idle / processing / success / error / duplicate).

`GroupRef` = record `({int chapterId, int groupIndex})`: `==`/`hashCode` per nilai udah bawaan Dart, gak perlu `freezed`.

### Alur import

1. Pilih file EPUB via `file_picker`
2. Baca bytes, hitung SHA-256 → kalau hash sudah ada → state **duplikat**
3. Parse EPUB di isolate (parser sendiri): judul, penulis, cover, chapter dari TOC/nav (bukan dari jumlah file HTML), `sortOrder` = urutan TOC. **Parse dulu sebelum nyalin file**, jadi EPUB jelek gak ninggalin apa-apa
4. Per chapter: parse HTML (package `html`), ambil blok teks (`p`, `div` berisi teks, heading, `hr`), normalisasi whitespace, buang paragraf kosong, lewati bagian non-isi (lihat bagian 14)
5. Jalankan `assignGroups` per chapter
6. Copy ke `Documents/books/{hash}.epub`, cover ke `Documents/covers/{hash}.{ext}`
7. Insert `books` + `chapters` + `paragraphs` dalam **satu transaksi** Drift
8. Gagal setelah nyalin → hapus file yang sudah di-copy (transaksi di-rollback), state **error**

Parsing buku besar bisa berat: jalankan di isolate (`compute` / `Isolate.run`) supaya UI tidak freeze.

### Posisi baca

- **Titik acuan** = paragraf paling atas yang keliatan di bawah safe area atas + `paragraphOffset` (bagian paragraf itu yang udah lewat garis tersebut, fraksi 0–1).
- **Nyimpen**: cuma setelah scroll dari jari (lompatan restore gak dihitung), debounce ±500 ms setelah scroll berhenti. Langsung disimpen pas app ke background (`AppLifecycleState` selain `resumed`), pindah bab, dan keluar halaman baca. Gak pernah nulis ke DB tiap frame.
- **Restore** (buka buku): lompat ke paragraf tersimpan, terus geser sesuai offset supaya titiknya ada di ±⅓ tinggi layar (ada konteks di atasnya). Tinggi paragraf baru ketahuan setelah layout, jadi dihitung di post-frame callback; isi bab disembunyiin sampe udah di posisi, terus fade in. Kepotong di ujung scroll kalau titiknya deket akhir chapter.
- Satu chapter dirender utuh (bukan list lazy), jadi posisi semua paragraf ketahuan tanpa package tambahan.

### Perilaku kapsul baca

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

### Persentase baca

`(chapters.charOffset + jumlah karakter paragraf sebelum posisi) / books.totalChars`.

Buku Markdown yang chapternya belum lengkap (nanti, bagian 13) tidak punya total yang pasti, jadi tampilkan progres per chapter saja.

### Gotcha iOS

- **Jangan simpan absolute path di database.** Path container app iOS bisa berubah setiap update/reinstall. Simpan nama file, gabungkan dengan `getApplicationDocumentsDirectory()` saat runtime.
- File dari picker biasanya ada di folder sementara, jadi wajib di-copy ke Documents.
- Buat folder `books/` dan `covers/` saat app start (`create(recursive: true)`).

---

## 9. Integrasi LLM

### Provider

OpenRouter (API OpenAI-compatible, base URL `https://openrouter.ai/api/v1`).

### Kandidat model (harga per 1 juta token, cek ulang di OpenRouter)

| Model | Model ID | Input | Output | Catatan |
|-------|----------|-------|--------|---------|
| GLM 5.3 Flash | `z-ai/glm-5.3-flash` | $0.075 | $0.25 | Termurah di tabel, tapi reasoning gak bisa dimatiin (token output lebih banyak) dan paling sering salah ketik |
| DeepSeek V4.1 Flash | `deepseek/deepseek-v4.1-flash` | $0.15–0.30 | $0.60–1.20 | Harga beda jam sibuk / tidak sibuk. **Default** (evaluasi #28) |
| Qwen 3.8 Flash | `qwen/qwen3.8-flash` | $0.15 | $0.47 | Keluarga Qwen kuat di multibahasa |

Estimasi: ~800 token input + ~400 token output per tap → dengan GLM 5.3 Flash sekitar **$0.16 per 1.000 tap**.

### Aturan implementasi

- **Model ID bisa diganti dari Pengaturan**, jangan di-hardcode.
- **Matikan reasoning** lewat parameter `reasoning` di request (token reasoning dihitung sebagai output dan bikin lambat).
- Minta output **JSON**; strip code fence sebelum `jsonDecode`.
- **Validasi** `translations.length` = jumlah paragraf grup. Kalau tidak cocok, retry sekali; kalau masih gagal, tampilkan state error.
- Timeout request ±30 detik → state error ("Yah, gagal nih"). Jalur streaming: dua tingkat, 15 detik tanpa token = "Agak lama nih..." (request tetep jalan), 30 detik = error; token berhenti 20 detik di tengah = kepotong.
- API key belum diisi → jangan panggil API, tampilkan state "API key belum diisi" dengan tombol ke Pengaturan.
- Untuk MVP pribadi, API key disimpan lokal di `flutter_secure_storage`. Kalau mau rilis, wajib lewat backend proxy.
- Atur preferensi provider di OpenRouter kalau ingin menghindari provider yang memakai data untuk training.

**Implementasi** (`OpenRouterService`):

- `POST /chat/completions` dengan `reasoning: {"enabled": false}` dan `response_format: {"type": "json_object"}`. Timeout connect/send/receive 30 detik.
- Sebagian model gak bisa reasoning-nya dimatiin (GLM 5.3 Flash: 400 "Reasoning is mandatory..."). Kena error itu → kirim ulang sekali dengan `reasoning: {"effort": "minimal", "exclude": true}`.
- Jawaban: ambil objek JSON dari `{` pertama sampe `}` terakhir (buang code fence / basa-basi), cek `translations` = list string sejumlah paragraf TARGET dan `meaning` gak kosong. Gak valid → coba ulang sekali, masih gagal → `invalidResponse`.
- Error bertipe (`AiError`): `noApiKey` (API gak dipanggil), `timeout`, `network`, `http` (bawa status: 401 key ditolak, 402 saldo abis), `invalidResponse`. Error HTTP gak di-retry.
- API key dibaca langsung dari Keychain tiap request (bukan di-cache), model dari `ai.model`.
- Key di Pengaturan (`ApiKeyEntry`): spasi / baris baru dibuang pas paste. Bentuk harus `sk-or-` + huruf/angka/`-`/`_` (min 8), kalau nggak pesan merah dan gak disimpen. Bentuk bener → `GET /key` (debounce 600 ms abis ngetik): 2xx → disimpen + "Key-nya jalan"; 401/403 → gak disimpen, "ditolak OpenRouter, jadi gak disimpen"; offline/gagal → disimpen aja, cuma keterangan Keychain. Teks ngawur atau key yang ditolak gak pernah nimpa key yang udah kesimpen. Key yang udah kesimpen dicek ulang tiap Pengaturan dibuka (401/403 → "Key-nya ditolak OpenRouter"). Tombol X di field ngosongin field dan ngehapus key dari Keychain (tanpa konfirmasi, sama kayak ngosongin field).
- **Streaming** (`explainStream`, dipakai sheet Artinya): `stream: true`, tanpa `response_format`, prompt sistem `aiStreamSystemPrompt` yang minta teks bersection, tiap penanda di baris sendiri: `[T1]` … `[Tn]`, terus `[MAKNA]`. SSE: baris `data:` dipotong per baris (baris yang kepotong di batas chunk ditahan, komentar `: OPENROUTER PROCESSING` dibuang), selesai di `data: [DONE]`. Ditutup sebelum `[DONE]` = `network`; event `{"error": ...}` di tengah = `http` dengan kodenya. Retry reasoning wajib sama kayak jalur biasa. `parseAiDraft` baca teks sebagian (teks sebelum penanda pertama dibuang, penanda kepotong di ujung ditahan); `parseAiSections` validasi akhir (penanda persis `T1..Tn, MAKNA`, gak ada yang kosong).
- **Ritme teks** (`Pacer`, pure): huruf ditampung lalu dikeluarin rata. Kecepatan = max(45 huruf/detik, buffer ÷ 1 detik), jadi ketinggalan maks ±1 detik; server selesai → sisa abis ≤ 600 ms; jawaban yang lengkap ≤ 1,5 detik sejak huruf pertama tampil langsung. Ini ganti aturan board (maks 2× baseline), lihat spike di bawah.
- **Spike streaming (#34, Okt 2026)**, 10 grup Pride and Prejudice (5 dialog 3–6 paragraf, 5 paragraf panjang 660–1080 huruf) × 3 model:

  | Model | Bersection valid | JSON valid | Token pertama (median / maks) | Total (median) | Alir huruf/detik (median, min–maks) |
  |-------|-----|-----|-----|-----|-----|
  | GLM 5.3 Flash | 10/10 | 9/10 | 0,96 / 2,7 dtk | 7,0 dtk | 219 (142–487) |
  | DeepSeek V4.1 Flash | 10/10 | 10/10 | 1,36 / 2,2 dtk | 4,7 dtk | 428 (90–1030) |
  | Qwen 3.8 Flash | 10/10 | 10/10 | 0,82 / 2,0 dtk | 6,7 dtk | 230 (199–263) |

  Token pertama 4–7× lebih cepat dari jawaban lengkap: streaming kerasa. Format bersection dipilih (lebih stabil, teks sebagian gampang diambil; penanda bisa diperluas buat nomor kalimat #36, mis. `[T1 K3-4]`). Simulasi ritme dari jadwal token asli: aturan board ketinggalan median 2,2–3,8 dtk (maks 5,4) lalu loncat pas selesai; aturan adaptif maks 1,8 dtk. Adaptif dipakai.
- Coba ke OpenRouter beneran: `make live` (key dari `.env` di root repo, `OPENROUTER_API_KEY=...`, di-gitignore), model lain `make live m=<model id>`. Tanpa key, test itu di-skip. Ketiga kandidat lulus (Okt 2026).

### Draft prompt

Versi prompt: `aiPromptVersion` (sekarang **4**: kenal buku + aturan gaya #40, aturan bahasa & makna #41, gaya luwes + istilah populer #28). Tiap isi prompt berubah, naikin angka ini: terjemahan yang dibikin pakai prompt lama diterjemahin ulang pas grupnya dibuka (`ai_results.promptVersion`).

**System** (bagian tugas sama buat dua format; penutupnya beda):

```
Kamu adalah asisten membaca. Pengguna sedang membaca buku berbahasa Inggris
dan ingin memahami bagian TARGET, yang terdiri dari satu atau beberapa
paragraf bernomor. BUKU dan BAB memberi tahu buku apa yang sedang dibaca.

Tugas:
1. Terjemahkan SETIAP paragraf TARGET ke Bahasa Indonesia yang natural,
   bukan kata per kata. Satu paragraf = satu item terjemahan. Jumlah dan
   urutan item harus sama dengan paragraf TARGET.
2. Jelaskan makna TARGET secara keseluruhan dalam 2–4 kalimat Bahasa
   Indonesia yang santai, kayak jelasin ke temen: apa maksud penulis,
   kaitannya dengan konteks sebelumnya, dan istilah sulit kalau ada.

Cara menerjemahkan:
- Pakai BUKU dan BAB untuk memahami konteks: siapa penulisnya, zamannya,
  dan aliran pemikirannya.
- Teks sumber sering terjemahan Inggris lama yang bahasanya kuno. Pahami
  maksudnya, lalu tulis ulang dalam Bahasa Indonesia modern yang enak
  dibaca. Jangan kaku dan jangan kata per kata, tapi maksudnya jangan
  bergeser.
- Istilah kunci (konsep filsafat, nama tokoh, tempat) tetap dipakai; kalau
  perlu, jelaskan singkat di bagian makna.
- Makna menjelaskan maksud penulis dan kaitannya dengan gagasan besar buku
  atau penulisnya, bukan mengulang terjemahan.

Bahasa:
- Ejaan Bahasa Indonesia yang benar. Periksa tiap kata: jangan ada kata
  rusak, salah ketik, atau kata bahasa Inggris yang nyelip (kecuali istilah
  kunci yang memang dipertahankan).
- Kata ganti konsisten: "you/thou/thee" = "kamu", "I/me" = "aku", "we" =
  "kita". Jangan pakai "engkau", "Anda", atau "saya".
- Terjemahan setia ke teks: jangan menambah keterangan dalam kurung,
  jangan menebak siapa tokoh yang disebut, jangan menambah kalimat yang
  tidak ada di teks. Penomoran (I., IX.) tetap ditulis.

Makna:
- Maksimal 4 kalimat. Fokus ke gagasan utama potongan ini dan istilah
  sulitnya.
- Kaitkan ke gagasan besar buku hanya kalau benar-benar membantu; jangan
  ditutup kalimat umum seperti "ini inti Stoisisme".
- Jangan mengaku nyambung dengan paragraf lain yang tidak ada di KONTEKS.
  Kalau tidak yakin soal fakta (siapa tokohnya, kapan), jangan ditulis.

Gaya dan istilah:
- Kalimat terjemahan harus luwes seperti tulisan orang Indonesia sekarang:
  pilih kata sehari-hari yang paling umum, jangan meniru urutan kalimat
  bahasa Inggris.
- Untuk konsep kunci, pakai padanan yang paling dikenal pembaca Indonesia
  sekarang (mis. "within our power" = "dalam kendali kita", bukan "dalam
  kuasa kita").
- Di bagian makna, kalau relevan, sebut istilah populer yang dikenal
  pembaca untuk gagasan itu (mis. dikotomi kendali, amor fati, memento
  mori) beserta penjelasan singkat. Kalau istilah itu bukan dari penulisnya
  sendiri, tulis jujur, mis. "sikap yang belakangan dikenal sebagai amor
  fati".

Contoh gaya terjemahan yang diinginkan:
"There are things which are within our power, and there are things which
are beyond our power." → "Ada hal-hal yang berada dalam kendali kita, dan
ada pula hal-hal yang di luar kendali kita."

KONTEKS hanya untuk membantu pemahaman, jangan diterjemahkan.
```

Penutup JSON (`aiSystemPrompt`, jalur tanpa streaming / retry):

```
Balas HANYA dengan JSON, tanpa teks lain:
{"translations": ["...", "..."], "meaning": "..."}
```

Penutup bersection (`aiStreamSystemPrompt`, streaming):

```
Balas HANYA dengan format ini, tanpa teks lain, tanpa markdown. Tiap
penanda di baris sendiri:
[T1]
terjemahan paragraf 1
[T2]
terjemahan paragraf 2
[MAKNA]
penjelasan makna
```

**User:**

```
BUKU: {judul}, {penulis}
BAB: {judul_bab}

KONTEKS (paragraf sebelumnya):
{paragraf_konteks}

TARGET:
[1] {paragraf_1}
[2] {paragraf_2}
...
```

Penulis kosong → `BUKU: {judul}` aja; judul bab kosong → baris BAB gak ada; grup pertama bab → gak ada KONTEKS. Data dari `books.title`, `books.author`, `chapters.title` (gak perlu re-import).

Contoh (`make live`, GLM 5.3 Flash, The Enchiridion bab I): makna langsung nyambung ke Stoisisme Epictetus ("pisahkan mana yang bisa kamu kendalikan...") dan istilah kunci dipertahankan.

**Evaluasi prompt (#41, Okt 2026).** 50 potong asli (25 The Enchiridion bab I–LI, 25 Meditations buku I–XII, Gutenberg #45109 dan #2680; panjang 101–4175 huruf, 4 grup multi-paragraf), GLM 5.3 Flash, jalur streaming:

| | v2 (#40) | v3 (sekarang) | v3 + brief/glosarium otomatis |
|---|---|---|---|
| Valid | 49/50 | 50/50 | 48/50 (`[MAKNA]` dobel) |
| Keterangan dalam kurung yang ditambah | 6 | 0 | 0 |
| Makna > 4 kalimat | 3 | 0 | 0 |
| Penutup generik ("inti Stoisisme"…) | 22 | 11 | 17 |
| engkau / Anda / saya | 5 | 7 (1 potong) | 6 |
| Kata rusak (perkiraan) | ±13 | ±11 | ±13 |

Temuan dari v1/v2 yang jadi dasar aturan v3: nebak tokoh ("Caius" jadi "Caligula"), keterangan dalam kurung di terjemahan, kata ganti campur (engkau/kamu/saya), makna kepanjangan dan ditutup basa-basi, ngaku nyambung ke paragraf yang gak ada.

- **v3 dikunci.** Aturan bahasa & makna ngilangin kurung, makna kepanjangan, dan setengah basa-basinya.
- **Brief + glosarium otomatis per buku: ditunda.** Brief dari GLM ngarang (nebak penerjemah, istilah Yunani karangan), dan versi yang udah dibenerin pun gak nangkep istilah yang penting ("opinion" di Epictetus tetap "pendapat", bukan "penilaian"). Dua jawaban jadi gak valid. Coba lagi kalau model brief-nya lebih kuat, atau lewat catatan manual per buku.
- **Kata rusak bukan urusan prompt.** Jumlahnya sama di semua versi ("menjadiapiclient", "kutyesali", "ketidakbehagian", "mementumori"…), ±1 tiap 4–5 potong. Ini kelemahan GLM: dibandingin di #28.
- Set 50 potong yang sama dipakai di #28.

### Evaluasi model

**Hasil (#28, Okt 2026).** Set 50 potong #41, prompt v3, jalur streaming, penilaian buta (A/B/C diacak per potong):

| | DeepSeek V4.1 Flash | Qwen 3.8 Flash | GLM 5.3 Flash |
|---|---|---|---|
| Valid | 49/50 | 50/50 | 49/50 |
| Terbaik (penilai Claude, 50 potong) | **29** | 11 | 10 |
| Terbaik (user, 6 potong) | 1 | **5** | 0 |
| Kata rusak (perkiraan) | ±2–3 | ±1–3 | ±13 |
| Biaya / 1000 tap (OpenRouter `usage`) | $0,36 | **$0,20** | $0,35 |
| Token pertama (spike #34) | 1,36 dtk | **0,82 dtk** | 0,96 dtk |

- **GLM dicoret dari default**: salah ketik paling banyak, ada arti yang kebalik.
- **Qwen** paling luwes, cepat, murah, dan disukai di bab awal Enchiridion (mis. "dalam kendali kita"), tapi beberapa kali salah fakta dengan yakin (Caius = Caligula, Antoninus "guru" Marcus), parafrase bebas, kata Inggris nyelip.
- **DeepSeek jadi default**: paling setia ke teks dan paling hati-hati soal fakta (Caius: "kemungkinan Julius Caesar atau Caligula"), makna paling kaya. Kelemahannya sedikit kaku: ditambal di prompt v4 (gaya luwes, padanan istilah yang dikenal pembaca, istilah populer seperti dikotomi kendali / amor fati dengan label jujur, satu contoh gaya). v4 dipasang tanpa evaluasi ulang atas keputusan user; dinilai lewat dogfooding (#29), ganti model tetap bisa dari Pengaturan.
- Biaya per tap sebenarnya beda dari tabel harga: GLM bukan yang termurah karena reasoning wajib.
- Glosarium per buku (mis. "power" → "kendali", "opinion" → "penilaian") masih ditunda; aturan v4 nanggung sebagian.

---

## 10. Backup & Restore

### Kenapa masuk MVP

Luma diinstall tanpa Apple Developer Program berbayar, jadi build harus diinstall ulang dari Xcode **setiap 7 hari**.

- Install ulang **di atas app yang sudah ada** (bundle ID & tim signing sama) biasanya **mempertahankan data**.
- Data **hilang** kalau app dihapus (mis. saat membereskan masalah signing), bundle ID berubah, atau ganti HP.

Terjemahan di `ai_results` dibayar pakai saldo OpenRouter dan progres baca tidak bisa dibuat ulang, jadi wajib ada backup manual yang gampang.

### Prinsip

- **Satu file berisi semuanya**, disimpan **di luar app** (Files / iCloud Drive / AirDrop ke Mac). Backup yang disimpan di dalam folder app ikut hilang kalau app dihapus.
- **Restore = ganti semua data** (bukan merge). Merge ditunda.
- **Aman**: restore diekstrak ke folder sementara dulu, data lama baru diganti kalau semua langkah berhasil.
- **API key tidak ikut** di-backup (alasan keamanan). Setelah restore, kalau API key kosong, app minta diisi ulang.

### Isi file backup

Nama: `luma-backup-YYYYMMDD-HHmm.zip` (pakai ekstensi `.zip` biasa supaya tidak perlu daftar tipe file custom di iOS).

```
luma-backup-20261006-2130.zip
├── manifest.json
├── luma.sqlite        ← snapshot database Drift
├── books/             ← file EPUB asli ({hash}.epub)
└── covers/            ← gambar cover ({hash}.png)
```

`manifest.json`:

```json
{
  "format": "luma-backup",
  "formatVersion": 1,
  "appVersion": "0.1.0",
  "schemaVersion": 1,
  "createdAt": "2026-10-06T21:30:00+07:00",
  "counts": { "books": 7, "aiResults": 1240 }
}
```

### Alur export (backup)

1. Pengaturan → "Backup sekarang"
2. Buat snapshot database yang konsisten dengan `VACUUM INTO '<tmp>/luma.sqlite'` (aman walau database sedang dipakai / mode WAL)
3. Tulis `manifest.json`
4. Zip snapshot + folder `books/` + `covers/` (pakai package `archive`, jalankan di isolate karena file EPUB bisa besar)
5. Buka share sheet (`share_plus`) → user pilih "Save to Files", iCloud Drive, atau AirDrop
6. Simpan `lastBackupAt` di tabel `settings`, hapus file zip sementara

**Implementasi** (`BackupService` + `BackupController`):

- Snapshot `VACUUM INTO` ke folder sementara (`Directory.systemTemp`), hitung jumlah buku & `ai_results` buat manifest. `appVersion` dari konstanta yang dicek sama `version` di pubspec (test).
- Zip di isolate (`Isolate.spawn` + port progres), urutan: `books/`, `covers/` (disimpen tanpa kompresi, udah kekompres), `luma.sqlite`, `manifest.json` (dikompres). Sheet "Lagi ngebungkus backup..." (board 26) nampilin nama file, persen, dan centang per tahap: buku → terjemahan (DB) → pengaturan (manifest). "Batalin" matiin isolate-nya, folder sementara dibuang.
- Sheet progres ditutup dulu, baru menu share iOS muncul. Backup terakhir cuma dicatet kalau share-nya **beneran disimpen/dikirim** (`ShareResultStatus.success`); ditutup tanpa milih = gak dicatet. Zip sementara selalu dihapus.
- Berhasil → toast "Backup kelar, aman!" + "12,4 MB · nama file" (board 27). Gagal → toast "Yah, backup gagal".
- Pengaturan, bagian "Backup & pulihin": kapan backup terakhir ("Barusan" kalau < 1 jam, "Kemarin", "3 hari lalu", ...), nama + ukuran file, atau "Belum pernah backup" (ikon pink). Tombol "Pulihin dari backup" nyusul di #25.
- Board nulis nama file `luma-backup-2026-10-06.luma`; yang dipake tetep `luma-backup-YYYYMMDD-HHmm.zip` (zip biasa, gak perlu daftar tipe file custom di iOS).

### Alur import (restore)

1. Pengaturan → "Pulihin dari backup" → pilih file `.zip` via `file_picker`
2. Ekstrak ke folder sementara
3. Validasi:
   - `manifest.json` ada dan `format` = `luma-backup`
   - `schemaVersion` backup **≤** schema app sekarang (backup dari versi lebih baru → tolak)
   - `luma.sqlite` bisa dibuka
4. Tampilkan ringkasan: jumlah buku, jumlah terjemahan, tanggal backup
5. Konfirmasi: "Semua data di Luma sekarang bakal diganti. Lanjut?"
6. Tutup koneksi Drift → ganti file database + folder `books/` & `covers/` → buka lagi database (migrasi Drift otomatis jalan kalau backup dari schema lama). Backup dari sebelum schema 4: terjemahannya jadi `promptVersion` 1, diterjemahin ulang pas grupnya dibuka
7. Invalidate provider Riverpod (atau restart ke Rak)
8. Gagal di langkah mana pun → hapus folder sementara, data lama tetap utuh

**Implementasi** (`RestoreService`, alurnya di Pengaturan):

- Pilih `.zip` (path lokal, dibaca streaming). Ekstrak di isolate ke `Directory.systemTemp`, **cuma file yang dikenal**: `manifest.json`, `luma.sqlite`, `books/<nama>`, `covers/<nama>`; path aneh (`../`, absolut, subfolder) dilewatin.
- Cek: bukan zip / manifest gak ada / `format` salah → "Ini bukan backup Luma"; `schemaVersion` > app → "Backup-nya dari Luma yang lebih baru" (nyebut dua versinya); `luma.sqlite` gak bisa dibuka → "File backup-nya rusak". Salinan sementara dibuka beneran (migrasi jalan di salinan), jadi database rusak ketauan sebelum apa pun diganti. Semua sheet gagal punya "Pilih file lain".
- Ringkasan (board 28): nama file, kapan & pake Luma versi berapa, jumlah buku & terjemahan, WarningBox (nyebut jumlah buku sekarang), ConfirmCheck; "Ganti & pulihin" baru aktif kalau dicentang. "Batal" = folder sementara dibuang.
- Ganti: tutup Drift → `books/`, `covers/`, `luma.sqlite(-wal/-shm)` dipindah ke `*.old` → isi backup dipindah masuk → `*.old` dihapus. Gagal di tengah → semua yang udah dipindah dibalikin urutan kebalik (ada test-nya). Abis itu `appDatabaseProvider` di-invalidate (database lama/baru dibuka lagi, provider data ikut dibangun ulang).
- Berhasil → balik ke Rak + toast "Sip, data lo udah balik!" · "N buku · N terjemahan"; kalau API key kosong, toast-nya punya baris kedua "API key gak ikut backup, isi ulang dulu biar bisa nerjemahin." + "Isi key" (6 detik). Gagal ganti → "Yah, gagal mulihin", data lama utuh.
- Teks board "File backup Luma itu yang akhirannya .luma" disesuaiin jadi nama `luma-backup-…zip`. Tile ringkasan dilabelin "terjemahan" (manifest ngitung baris `ai_results` = grup, bukan paragraf).

### Pengingat backup

- Pengaturan menampilkan "Backup terakhir: 3 hari lalu" (atau "Belum pernah backup").
- Kalau `lastBackupAt` lebih dari **6 hari** (sebelum siklus install ulang 7 hari), tampilkan banner kecil di Rak: "Udah 6 hari belum backup nih" dengan tombol "Backup".
- Banner bisa ditutup, muncul lagi besoknya.
- **Implementasi:** hitungan per tanggal kalender dari backup terakhir; kalau belum pernah backup, dari buku pertama yang diimport (rak kosong = gak ada banner). Muncul mulai hari ke-6. Ditutup → tanggalnya disimpen di `settings` (`backup.reminderDismissedAt`), nongol lagi besok. Banner pink (board 24) ada di paling atas area scroll Rak; teksnya: hari ke-6 "Udah 6 hari belum backup nih" · "Besok jatah install ulang. Amanin data lo dulu yuk.", lebih dari itu "Udah N hari belum backup nih" · "Amanin data lo dulu yuk, sebelum keburu install ulang.", belum pernah "Belum pernah backup nih" · "Data lo cuma ada di HP ini doang. Amanin dulu yuk.". "Backup sekarang" langsung jalanin backup di Rak (sheet progres & toast-nya sama kayak di Pengaturan).

### Catatan

- Jangan bandingkan absolute path dari backup. Semua path di database sudah berupa nama file (bagian 6), jadi tetap valid setelah restore.
- Ukuran backup kira-kira = total ukuran EPUB + sedikit untuk database. Tampilkan ukuran setelah backup selesai.
- Unit test: round-trip export → restore ke database kosong menghasilkan data yang sama.

### Ditunda (setelah MVP)

- Export/import **per buku** (satu buku + terjemahannya, untuk dipindah atau dibagikan)
- Restore **merge** (gabung dengan data yang ada)
- Export terjemahan + makna ke Markdown (nyambung dengan Recap)

---

## 11. Urutan Pengerjaan

1. Setup project: struktur dari Mibu, Drift, go_router, theme Stabilo (`ThemeExtension` + font asset)
2. Schema Drift: `books`, `chapters`, `paragraphs`, `reading_progress`, `ai_results`, `settings` (pakai `chapters.id` sebagai kunci, lihat bagian 6)
3. `assignGroups` + unit test
4. Import EPUB: copy file, metadata, cover, parse chapter → paragraf → grup (isolate + transaksi), state import
5. Rak buku: kosong + berisi + kartu "Lanjut baca yuk" + cover default
6. Halaman baca + Daftar isi + Aa
7. Tap grup → highlight + bottom sheet (loading / hasil / error) + OpenRouter
8. Cache `ai_results`
9. Simpan & restore posisi baca + persentase
10. Pengaturan: API key, model ID, hapus cache
11. Backup & restore (bagian 10) + pengingat backup
12. Dogfooding, catat pain point di bagian 14

---

## 12. Iterasi 2: Recap Bacaan

### Tujuan

Misal sudah baca 18% buku. Pengguna bisa membuka layar Recap untuk:

1. Melihat **terjemahan + makna semua paragraf** dari awal sampai posisi baca sekarang, dikelompokkan per chapter.
2. Membaca **overview "sejauh ini"**: ringkasan keseluruhan bagian yang sudah dibaca.

Berguna untuk baca sekilas ulang tanpa harus tap paragraf satu per satu.

### Prinsip

- **Bebas spoiler**: tidak pernah memproses teks setelah posisi baca terakhir.
- **Reuse cache**: hasil disimpan ke `ai_results` yang sama dengan fitur tap, **per grup**. Grup yang diproses lewat Recap langsung instan saat di-tap di reader, dan sebaliknya.
- **Unit = grup** (bagian 7), bukan paragraf tunggal.
- **Per chapter, bukan per halaman**: EPUB bersifat reflowable, jumlah "halaman" berubah tergantung ukuran font dan layar. Chapter adalah unit yang stabil.
- **Persentase** dihitung dari posisi paragraf (atau jumlah karakter) terhadap total buku.

### Bagian A: Terjemahan + makna semua yang sudah dibaca

Alur:

1. Buka layar Recap
2. Cari grup dari awal buku sampai posisi baca yang **belum** ada di `ai_results`
3. Proses yang belum ada dalam **chunk beberapa grup per request** (mis. 3–5 grup, ±1.500–2.500 karakter)
4. Simpan hasil per grup ke `ai_results`
5. Tampilkan bertahap sambil job berjalan

Format balasan LLM per chunk:

```json
[
  {"group": 12, "translations": ["...", "..."], "meaning": "..."},
  {"group": 13, "translations": ["..."], "meaning": "..."}
]
```

Validasi: pastikan setiap `group` yang dikirim ada di balasan dan jumlah `translations` cocok dengan jumlah paragrafnya. Grup yang hilang atau gagal di-parse masuk antrean retry.

Draft prompt chunk (system):

```
Kamu adalah asisten membaca. Teks dibagi menjadi beberapa GRUP bertanda
[grup N], tiap grup berisi satu atau beberapa paragraf. Untuk SETIAP grup:
terjemahkan tiap paragrafnya ke Bahasa Indonesia yang natural (satu item
per paragraf, urutan sama), lalu beri satu penjelasan makna singkat
(1–3 kalimat, santai). Gunakan KONTEKS hanya untuk pemahaman.

Balas HANYA dengan JSON array, satu objek per grup:
[{"group": <int>, "translations": ["..."], "meaning": "..."}]
```

### Bagian B: Overview "sejauh ini"

Pakai **ringkasan bertingkat**, jangan kirim seluruh teks yang sudah dibaca setiap kali:

1. **Chapter selesai dibaca** → buat ringkasan chapter sekali, simpan.
2. **Chapter yang sedang dibaca** → buat ringkasan sampai paragraf terakhir yang dibaca. Update kalau posisi baca sudah maju cukup jauh.
3. **Overview keseluruhan** → dibuat dari gabungan ringkasan chapter, bukan dari teks mentah.

Hasilnya lebih murah, lebih cepat, dan otomatis bebas spoiler.

### Tambahan data model

**`chapter_summaries`**

| Kolom | Tipe | Catatan |
|-------|------|---------|
| chapterId | int (FK) | |
| summary | text | Bahasa Indonesia |
| coveredUntilParagraph | int | Sampai paragraf mana ringkasan ini dibuat |
| model | text | |
| updatedAt | datetime | |

Unique key: `(chapterId)`.

**`book_overviews`**

| Kolom | Tipe | Catatan |
|-------|------|---------|
| bookId | int (PK) | Satu overview aktif per buku |
| overview | text | |
| coveredUntilChapterId | int | |
| coveredUntilParagraph | int | |
| progressPercent | real | Persentase saat overview dibuat |
| updatedAt | datetime | |

Overview dibuat ulang kalau posisi baca sudah maju melewati ambang tertentu (misal +5% atau ganti chapter).

### Layar Recap

- **Atas**: kartu overview "Sejauh ini (18%)"
- **Bawah**: daftar chapter (expand/collapse), masing-masing dengan ringkasan chapter
- **Saat chapter dibuka**: paragraf dengan terjemahan + makna
- **Toggle tampilan**: terjemahan saja / makna saja / berdampingan dengan teks asli
- **Tap paragraf** → lompat ke posisi tersebut di reader
- **Progress bar** saat job berjalan, misal "45 / 120 bagian"

### Catatan implementasi

- Job pengisian dibuat sebagai Riverpod `Notifier` yang menyimpan state progres (total grup, selesai, gagal).
- Batasi **3–5 request paralel**, pakai retry dengan backoff, dan sediakan tombol batal.
- iOS akan menghentikan proses saat app ditutup atau masuk background. Karena hasil disimpan per paragraf, job cukup **melanjutkan yang belum selesai** saat app dibuka lagi.
- Pakai endpoint OpenRouter **standar**, bukan varian `:batch`. Untuk GLM 5.3 Flash, varian batch justru lebih mahal (per Oktober 2026).
- Opsional: **prefetch** beberapa paragraf ke depan di background saat membaca, supaya tap terasa instan dan Recap makin lengkap.

### Estimasi biaya

Buku rata-rata sekitar 100 ribuan token teks. Dengan GLM 5.3 Flash, terjemahan + makna **satu buku penuh** kira-kira **~$0.10**. Recap 18% hanya beberapa sen. Tantangan utama ada di UX dan kecepatan, bukan biaya.

### Urutan pengerjaan Iterasi 2

1. Job pengisian grup yang belum diterjemahkan (chunk + progress + retry)
2. Layar Recap: daftar chapter + paragraf + toggle tampilan
3. Ringkasan per chapter (`chapter_summaries`)
4. Overview keseluruhan (`book_overviews`)
5. Lompat dari Recap ke posisi di reader

---

## 13. Ide Kasar: Import Luma Markdown, Foto Buku Fisik & Format Lain

> Status: ide kasar, belum final. Kandidat **Iterasi 3**. Yang sudah diambil ke MVP hanya keputusan skema (ID chapter stabil + `sourceType` + `bookKey`, bagian 6).

### Konsep umum

Format internal (**buku → chapter → paragraf → grup**) sudah dipakai di MVP untuk EPUB. Format lain cukup ditambah sebagai **importer baru** yang menghasilkan struktur yang sama. Reader, tap terjemahan, cache, dan Recap tidak perlu diubah.

```
EPUB ─────────┐
Luma Markdown ┼─► Importer ─► chapters + paragraphs + groups (Drift) ─► Reader / AI / Recap
PDF (nanti) ──┤
TXT (nanti) ──┘
```

### Skenario utama: baca buku fisik per chapter

Contoh: lagi baca Atomic Habits versi fisik.

1. Foto semua halaman chapter 3 (misal 10 foto)
2. **Di luar Luma**: kirim foto ke LLM (chat Claude/Gemini, atau nanti script) dengan prompt template di bawah → hasil file `.md` format Luma Markdown
3. Import `.md` ke Luma → buku "Atomic Habits" baru muncul di rak dengan satu chapter
4. Minggu depan lanjut chapter 7: foto → convert di luar → import `.md` → **otomatis masuk ke buku Atomic Habits yang sama**, terurut setelah chapter 3

Pembagian kerja: semua urusan foto, OCR, dan konversi ada **di luar app**. Luma hanya tahu cara import file Markdown yang sudah jadi.

### Format Luma Markdown (v1)

Satu file = satu chapter. Info buku dan chapter ada di frontmatter.

```markdown
---
luma: 1
book_key: atomic-habits
book: Atomic Habits
author: James Clear
chapter: 3
chapter_title: How to Build Better Habits in 4 Simple Steps
---

Paragraf pertama, utuh walaupun di buku aslinya terpotong
pindah halaman.

Paragraf kedua.

## Subjudul di dalam chapter

Paragraf setelah subjudul.

***

Paragraf setelah pemisah adegan.
```

Aturan:

| Elemen | Aturan |
|--------|--------|
| Frontmatter | `luma` (versi format), `book_key` (wajib, slug huruf kecil + strip), `book`, `author`, `chapter` (angka), `chapter_title` |
| Paragraf | Dipisah **satu baris kosong**. Baris yang tidak dipisah baris kosong = paragraf yang sama |
| Subjudul | `##` → `type = heading` |
| Pemisah adegan | `***` → `type = scene_break` |
| Format inline | Boleh `*miring*` dan `**tebal**`, selain itu teks polos |
| Dilarang | Nomor halaman, header/footer halaman, catatan "[gambar]" bebas tanpa aturan |

`book_key` adalah kunci pencocokan buku. Lebih aman daripada mencocokkan judul yang rawan beda tulisan.

### Logika import di Luma

1. Pilih file `.md` via `file_picker`
2. Parse frontmatter
3. **Tidak ada frontmatter** → tanya lewat UI: masuk ke buku mana (atau buat baru) + chapter berapa
4. `book_key` **belum ada** → buat buku baru (`sourceType = markdown`, cover default)
5. `book_key` **sudah ada** → tambahkan chapter ke buku itu
6. Nomor `chapter` **sudah ada** di buku itu → tanya: ganti atau batal. Kalau ganti: hapus chapter lama beserta `ai_results`-nya
7. Hitung `sortOrder` dari nomor chapter, sisipkan di posisi yang benar, hitung ulang `charOffset`
8. Parse body → paragraf → `assignGroups` → insert dalam satu transaksi
9. Toast: "Bab 7 masuk ke Atomic Habits ✨" (copy final menyesuaikan desain)

UI tambahan nanti:

- Daftar isi buku Markdown menampilkan bab yang belum ada secara samar, misal "Bab 4–6 belum ada"
- Progres baca per chapter (total buku tidak diketahui)
- Tombol "Tambah chapter" di halaman/aksi buku → langsung buka file picker dengan buku sudah terpilih

### Prompt template konversi foto (dipakai di luar app)

```
Kamu akan menerima foto halaman-halaman satu chapter dari buku fisik.
Ubah menjadi satu file Markdown dengan format persis seperti di bawah.

Aturan WAJIB:
1. Transkripsi PERSIS. Jangan memparafrase, meringkas, menerjemahkan,
   atau memperbaiki kata/ejaan dari buku.
2. Urutkan halaman berdasarkan nomor halaman yang tercetak, bukan urutan
   foto kalau berbeda.
3. Sambung paragraf yang terpotong antar halaman menjadi satu paragraf utuh.
4. Sambung kata yang terpotong tanda hubung (-) di ujung baris.
5. Buang nomor halaman, header, dan footer halaman.
6. Pisahkan paragraf dengan SATU baris kosong. Jangan memecah satu
   paragraf menjadi beberapa baris.
7. Subjudul di dalam chapter pakai "## ". Pemisah adegan pakai "***".
8. Miring pakai *teks*, tebal pakai **teks**. Selain itu teks polos.
9. Gambar/diagram: tulis satu baris "[Gambar: deskripsi singkat]" sebagai
   paragraf sendiri. Tabel: tulis isinya sebagai paragraf biasa.
10. Kalau ada bagian yang tidak terbaca, tulis [tidak terbaca], jangan
    menebak.

Isi frontmatter berikut (nomor dan judul chapter boleh kamu baca dari
halaman pertama chapter):

---
luma: 1
book_key: {book_key}
book: {judul buku}
author: {penulis}
chapter: {nomor chapter}
chapter_title: {judul chapter}
---

Balas HANYA dengan isi file Markdown, tanpa penjelasan lain.
```

Catatan:

- Kirim foto dalam satu percakapan sekaligus (atau per 3–5 foto lalu minta lanjutkan), supaya paragraf antar halaman bisa disambung.
- Pakai **`book_key` yang sama** untuk semua chapter dari buku yang sama. Simpan daftar `book_key` di catatan.
- Foto lebih bagus pakai document scanner (auto crop + luruskan perspektif), misal fitur scan di app Files/Notes iPhone.
- Cek cepat hasilnya sebelum import: risiko terbesar adalah LLM mengubah kata atau melewatkan paragraf.
- Nanti kalau sering dipakai: jadikan script kecil (mis. Python) yang memanggil OpenRouter dengan model vision (GLM 5.3 Flash / DeepSeek V4.1 Flash / Qwen 3.8 Flash menerima gambar) dan langsung menulis file `.md`.

### Opsi support PDF

| Jalur | Cara | Kelebihan | Kekurangan |
|-------|------|-----------|------------|
| 1. Convert di luar app | Marker / Docling (PDF → Markdown) lalu sesuaikan ke format Luma Markdown, atau Calibre (PDF → EPUB) | Nol kode tambahan, cocok untuk sekarang | Manual, hasil Calibre sering berantakan |
| 2. Parse di app | `pdfrx` ekstrak teks + heuristik (sambung baris, hapus hyphen, buang header/footer, deteksi paragraf dari jarak/indentasi) | Langsung dari HP | Banyak trial-error, tiap PDF bisa beda |
| 3. Parse dengan LLM | Kirim teks atau gambar halaman ke LLM, minta JSON paragraf | Bisa handle PDF scan, hasil rapi | Risiko teks berubah dari aslinya, perlu instruksi tegas |

Setelah importer Luma Markdown ada, jalur 1 jadi jalur default untuk PDF: PDF → Markdown di luar app → import.

### Format lain yang mungkin disupport

- **TXT**: paling gampang
- **HTML**: relatif mudah (EPUB pada dasarnya HTML)
- **MOBI / AZW3**: convert ke EPUB via Calibre dulu
- File dengan **DRM** tidak bisa diparse

### Urutan pengerjaan kasar (Iterasi 3)

1. Parser frontmatter + body Luma Markdown + unit test
2. Logika import: buku baru / tambah chapter / chapter duplikat
3. Sisip chapter + hitung ulang `sortOrder` & `charOffset`
4. UI: import `.md`, dialog tanpa frontmatter, dialog ganti chapter, toast
5. Daftar isi dengan bab bolong + progres per chapter
6. (Opsional) Script konversi foto → `.md` via OpenRouter

---

## 14. Catatan & Ide (raw)

_Tempat dump ide selama dogfooding. Triage seminggu sekali._

- **Bagian non-isi buku (Okt 2026, belum final).** Import cuma buang yang pasti bukan isi, dikenali dari struktur (bukan judul): lisensi Gutenberg, halaman daftar isi / indeks (kebanyakan isinya link), dan chapter kosong / cuma judul. Introduction, Notes, Appendix, Glossary, dan iklan penerbit tetep disimpen: salah buang = isi hilang + cache terjemahan ikut kehapus pas re-import, sedangkan kelebihan satu bab cuma nambah satu entri. Pantau pas dogfooding: kalau Introduction ganggu, opsinya buku dibuka langsung di bab isi pertama, bukan dibuang.
- **Streaming response di sheet Artinya (Okt 2026, ide, prioritas rendah).** Teks terjemahan + makna muncul begitu model mulai nulis. Dipecah dua: logika (spike format output + ukur kecepatan alir, klien SSE, state machine, cache, pacing; di balik flag, sheet lama gak berubah) di [#34](https://github.com/choiruladamm/luma/issues/34), UI sheet (ritme, pudar, status tombol, scroll) di [#38](https://github.com/choiruladamm/luma/issues/38). Cuma dua spike di #34 yang jalan dulu; abis Spike 2 ada gerbang keputusan: lanjut = sisa #34 dikerjain dan #38 dibuka (setelah #37 ke-merge), nggak = #34 ditutup dengan hasil spike.
- **Highlight sinkron per paragraf (Okt 2026, ide).** Scroll terjemahan di sheet Artinya → paragraf asli pasangannya disorot dan halaman ikut scroll (satu arah). Pakai array `translations` yang udah ada, gak ubah prompt/cache. Detail: [#35](https://github.com/choiruladamm/luma/issues/35).
- **Highlight sinkron per kalimat (Okt 2026, ide, tunggu data dogfooding).** Level 2 dari #35 buat paragraf tunggal yang lebih tinggi dari ruang di atas sheet. Butuh pemecah kalimat berversi + format `ai_results` baru (migrasi). Tutup kalau kasusnya jarang. Detail: [#36](https://github.com/choiruladamm/luma/issues/36).
- **Sheet Artinya ikut Aa + header/tombol ngumpet pas scroll (Okt 2026).** Teks isi sheet ikut font/ukuran/jarak/margin Aa, header + Salin/Lanjut geser keluar pas scroll (board Opsi A · geser ngikut, area baca 335 → 516pt). Ada beberapa hal yang perlu diputusin dulu (tinggi sheet 528 vs "ngikutin isi maks 70%", swipe turun nutup). Detail: [#37](https://github.com/choiruladamm/luma/issues/37).
- **Lanjut lintas bab di sheet Artinya (Okt 2026, ide, nunggu desain).** Sekarang Lanjut mati di grup terakhir bab. Usulan: tetap aktif dan pindah ke grup pertama bab berikutnya (halaman ikut pindah, bab tanpa grup dilewati). Desainnya dibikin user dulu, belum dikerjain. Detail: [#39](https://github.com/choiruladamm/luma/issues/39).
- **Statistik baca (Okt 2026).** Pencatatan dulu, layar belakangan, karena datanya gak bisa di-backfill. Dua log append-only (`reading_sessions` buat potongan waktu baca + posisi karakter, `ai_calls` buat token/biaya/latensi tiap request LLM) plus `books.finishedAt` dan `ai_results.openCount`; semua statistik dihitung lewat query, tanpa tabel rollup. Schema v5 + pencatatan di milestone MVP sebelum dogfooding; tampilan (streak, heatmap, kecepatan, tren AI per 1.000 karakter, bab tersulit, biaya) ide tanpa milestone. Induk: [#42](https://github.com/choiruladamm/luma/issues/42), rincian di sub-issue #43–#58. Skema final ditulis ke bagian 6 di #43.
- **Pilih gateway AI (Okt 2026, raw idea).** Kayak opencode: pilih gateway → paste key gateway itu → pilih model sesuai aturan ID gateway itu. Dua gateway dulu, tanpa endpoint custom: OpenRouter dan CheaperInference (versi hosted OmniRoute, saldo top-up). Mulai dari eval pakai korpus #41 (kualitas, biaya, kemungkinan kompresi di sisi mereka, versi model); hasil jelek = ditutup. Gak nyambung ke statistik; `ai_calls.provider` baru ditambah pas fitur ini jadi. Detail + temuan API: [#59](https://github.com/choiruladamm/luma/issues/59).
