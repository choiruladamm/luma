# Desain: Stabilo

Referensi lengkap (layar, komponen, token): https://claude.ai/artifact/EBwv9zJBLZQJa5WWYiaJ7F

## Prinsip

1. **Teks dulu, UI belakangan.** Halaman baca bersih. UI muncul hanya saat dibutuhkan (sheet artinya, Aa, progres tipis di bawah).
2. **Kuning = yang lagi penting.** Stabilo hanya untuk aksi utama dan paragraf/grup yang sedang di-tap. Satu layar, satu tombol kuning.
3. **Malem tetep adem.** Mode gelap pakai hitam hangat, bukan hitam pekat.

## Font

| Font | Dipakai untuk |
|------|---------------|
| Bricolage Grotesque | UI, judul, label, tombol |
| Atkinson Hyperlegible | Teks bacaan + isi sheet (default, opsi "Jelas") |
| Literata | Opsi bacaan "Kayak buku" |
| Font sistem iOS | Opsi bacaan "Bawaan iOS" |

Bundle font sebagai asset (jangan fetch runtime).

## Token warna utama

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

## Halaman baca imersif (ReaderCapsule)

Pas baca, layar isinya cuma teks + garis progres tipis. Menu nongol sebagai dua kapsul ngambang kalau dibutuhin. Top bar 60pt cuma buat Rak & Pengaturan. Spek lengkap di board "Baca imersif · ReaderCapsule" (+ layar 03 Baca, 03b imersif, 03c Lanjut baca).

- **Kapsul atas**: tinggi 58, radius penuh, 6pt di bawah safe area atas, kiri-kanan 24. Isi: balik · judul + "Bab N · judul bab" · daftar isi · Aa. Tombol 44 bulet muted; tombol yang sheet-nya lagi kebuka (Daftar isi / Aa) jadi kuning.
- **Kapsul bawah**: tinggi 40, 14pt di atas safe area bawah, di tengah. Persen + bar 88 + "±N mnt lagi" (atau "Bab N beres"). Cuma info.
- **Gaya kapsul**: latar sheet. Terang: garis 1,5 ink + bayangan tekan 2 + bayangan lembut. Gelap: garis `#46423A` + bayangan lembut.
- Teks yang lewat di belakang kapsul dimudarin pake **EdgeFade** (lihat di bawah), bukan gradien warna latar.
- **Garis progres** 2pt selebar layar, tepat di atas safe area bawah (gak kepotong sudut layar, gak numpuk home indicator). Terang `#E6B800`, gelap `#E9C75A`, track ink 8–10%. Progres per buku; 100% di layar akhir buku.
- Kapsul itu **overlay**: teks gak loncat pas kapsul muncul/ngumpet. Teks awal bab mulai 86pt di bawah safe area atas (board: 140) biar judul bab gak ketutup.

## EdgeFade (tepi area scroll)

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

## Pengaturan Aa

Sheet "Atur bacaan lo" (board 07), dibuka dari tombol Aa di kapsul. Tiap pilihan langsung disimpen dan langsung keliatan di teks; scrim-nya tipis (8% terang, 18% gelap) biar teks di belakang jadi preview. Posisi baca nempel: titik yang lagi di garis atas tetep di situ pas ukuran/font/jarak/margin diganti.

- Ukuran huruf: 7 step 16 · 17 · 18 · **18,5** · 20 · 22 · 24 (tombol A kecil / A gede)
- Font: **Jelas** (Atkinson Hyperlegible) / Kayak buku (Literata, jarak baris +0,05) / Bawaan iOS (SF)
- Jarak baris: Rapat 1,5 / **Pas 1,65** / Lega 1,85; mode gelap +0,05
- Margin teks: Sempit 16 / **Pas 24** / Lega 32. Area tap margin minimal 24pt: di Sempit, 8pt pinggir kolom ikut diitung area kosong
- Tema: Terang / Gelap / **Ikut iOS** → `themeMode` app
- Tampilan layar: "Sembunyiin jam & baterai" (**nyala**) dan "Tampilin garis progres" (**nyala**), pake Switch dari board Komponen dasar (51 × 31)
- Disimpen per perangkat (bukan per buku) di tabel `settings`, ikut backup. Nilai yang gak dikenal (backup rusak) balik ke default

## Sheet Artinya: ikut Aa, header & tombol ngumpet pas scroll

Board "Spek · Artinya ngumpet pas scroll" dan "Terpilih · Artinya ngumpet pas scroll · Opsi A (geser ngikut)": area baca nambah 54% (335 → 516pt di sheet 528).

- **Teks ikut Aa:** terjemahan dan blok makna pakai font, ukuran, jarak baris, dan margin yang sama dengan halaman baca (`ReaderTypography`, satu sumber buat dua-duanya). Padding dasar sheet (24) jadi batas bawah margin: Sempit (16) sama kayak Pas, Lega (32) nambah 8 di kiri-kanan isi. Judul, chip, tombol, toast, dan teks pesan error / API key kosong tetap ukuran UI. Placeholder loading pakai tinggi baris yang sama. Ganti Aa langsung kebawa (provider yang sama).
- **Struktur:** sheet 528 (62,5% layar, `DraggableScrollableSheet`, semua state). Isi scroll setinggi sheet, padding atas 91 / bawah 102 (tombol 52 + jarak 16 + safe area 34). Header (judul + X), grabber, dan Salin / Lanjut lapisan di atas isi, jadi ngilangnya header gak geser teks.
- **Ngumpet (cuma scroll dari jari; scroll programatik gak ngitung):** header ikut isi 1:1 pas turun dan ilang setelah 91pt; naik ≥ 12pt → turun lagi ngikutin jari dari atas, dilepas di tengah snap ke yang terdekat. Salin / Lanjut geser keluar setelah turun ≥ 24pt (200ms, ease-out), balik pas naik ≥ 12pt atau mentok bawah. Header tetap ngumpet sampai scroll naik; balik ke paling atas = semua lengkap. Ambang (24 / 12) dari `ScrollRun`, dipakai bareng kapsul baca.
- **Gak pernah ngumpet:** isi muat semua, state loading / error / API key kosong, VoiceOver nyala. Kurangi gerakan: gak geser, gak ngikutin jari, fade 150ms.
- **Nutup:** swipe turun di grabber (ngikutin jari, nutup kalau di-fling atau ditarik jauh, pas offset berapa pun), swipe turun di isi pas offset 0, atau tap area kosong di atas sheet (bukan munculin kapsul baca).
- **Tinggi area baca yang keliatan** (`MeaningChrome.readHeight`): tinggi sheet dikurangi chrome yang keliatan, buat highlight sinkron (#35).

## Sheet Artinya: streaming

Board "Terpilih · Artinya streaming · Opsi B · muncul halus (diperbaiki)" dan "Artinya streaming · perilaku". Sumbernya `groupAiStreamProvider` ([architecture.md](architecture.md)). Grup yang udah ke-cache langsung tampil jadi, tanpa ritme dan tanpa ikut turun. Satu widget buat semua tahap (`_Answer`), jadi pas selesai gak ada loncatan layout dan posisi scroll gak di-reset. Tinggi sheet tetap 528 di semua tahap.

- **Tahap:** nunggu (header "Bentar, lagi mikir...", placeholder per paragraf + makna) → nulis terjemahan (paragraf masuk berurutan, sisanya placeholder) → nulis makna → selesai (header "Artinya gini nih", Salin aktif). Header cuma judul + X, tanpa chip.
- **Kelamaan** (15 detik tanpa token): kartu "Agak lama nih..." di atas isi (Batal / Coba lagi). Token masuk → kartunya ilang sendiri. **Kepotong**: teks yang udah masuk tetep, placeholder dibuang, banner pink "Yah, kepotong di tengah" + Coba lagi (mulai dari awal).
- **Ritme:** huruf keluar per frame ngikutin `Pacer` ([llm.md](llm.md)). **Deviasi dari board (2):** aturan adaptif, bukan maks 2× baseline (data spike #34).
- **Ujung teks:** gak ada kursor, kedip, atau kuning di teks. 4 kata terakhir bagian yang lagi ditulis opasitas 80 · 60 · 42 · 26%, diem (`Text.rich`); selesai → solid dalam 300 ms. **Deviasi dari board (1):** tanpa fade-in 150 ms per potongan, karena teks keluar per huruf dan dua efek itu numpuk.
- **Tombol:** Salin / Lanjut dikunci keliatan selama belum selesai. Salin nonaktif; statusnya di tombol itu: tiga titik 4pt berdenyut (opasitas 30 ↔ 85%, 1,6 detik) + "Lagi mikir" / "Lagi nulis", ink2 di atas muted. Selesai → crossfade 150 ms ke "Salin". Kelamaan / kepotong: "Salin" abu, statusnya di kartu / banner. Lanjut mati selama masih diproses (nunggu, kelamaan, nulis), aktif lagi pas selesai atau kepotong (deviasi dari board, yang Lanjut-nya selalu aktif). Batalin di tengah = X ("Batalin" di VoiceOver), tutup sheet = request dibatalin.
- **Gak bisa di-scroll sebelum teks pertama masuk** (nunggu / kelamaan): isinya cuma placeholder. Nutup lewat X, grabber, atau tap di atas sheet (swipe di isi gak nutup di tahap ini).
- **Gak ikut turun (deviasi dari board, Okt 2026):** isi gak di-scroll otomatis. Sheet diem di awal terjemahan biar bisa dibaca dari paragraf pertama sementara sisanya ditulis di bawah; scroll cuma dari jari. Gak ada tombol "Ke bawah". Header ikut isi 1:1 pas di-scroll selama streaming (kayak bagian dari isi), tombol gak ngumpet; abis selesai, aturan ngumpet biasa nerusin dari posisi header terakhir.
- **Placeholder ikut Aa:** baris = ⌈huruf × lebar huruf rata-rata ÷ lebar kolom⌉, huruf = panjang paragraf asli × 1,05 (makna 130). Lebar huruf rata-rata diukur pakai `TextPainter` dari font + ukuran Aa yang aktif (bukan konstanta per font). Tinggi baris = baris teks. Isi tumbuh ke bawah.
- **Kurangi gerakan:** teks muncul per bagian utuh (satu paragraf, lalu makna), tanpa pudar, titik diem, placeholder tanpa shimmer.
- **VoiceOver:** sheet berlabel "Artinya, lagi ditulis"; bagian yang lagi ditulis gak dibacain sampai utuh; selesai → diumumin "Artinya udah lengkap".

## Bedahin

Board "Terpilih · Bedahin · Opsi C · layar bedah" + "Spek · Bedahin · state" (terang + gelap). Layar sendiri (`BreakdownView`, route di [architecture.md](architecture.md)), sumbernya `breakdownStreamProvider`. Semua aturan streaming sheet Artinya (ritme `Pacer`, 4 kata memudar, placeholder shimmer, status di tombol Salin, kurangi gerakan, VoiceOver) berlaku juga di sini.

- **Entri** di sheet Artinya: item terakhir isi, abis maksud, ikut ke-scroll, semua grup. "Masih bingung? Bedahin" / "Buka bedahan · Udah pernah dibedah · N bagian" (`breakdownSectionsProvider`). Gak muncul selama makna masih ditulis atau kepotong; muncul pakai fade 150ms. Nunggu jumlah bagian dari DB dulu biar copy-nya gak ganti di depan mata.
- **Header:** balik (VoiceOver "Batalin, balik ke Artinya" selama proses) + status ("Lagi ngebedah..." / "Udah dibedah nih" / "Kepotong di tengah" / "Bedahin" pas error) + "buku · bab · N bagian" ("1 gagasan", "N bagian masuk" pas kepotong).
- **Panel teks** (terjemahan, ikut Aa) selalu ada di semua state, termasuk nunggu dan error. Nomor bagian di depan kalimat pertama tiap bagian, cuma kalau ≥ 2 bagian; selama nulis nomornya muncul bareng penjelasan bagiannya. Grup > 1 paragraf: jarak 12 + `¶n` di kolom kiri, bagian yang nyebrang paragraf dapet tag `¶2–3` (**deviasi dari board C6**, ikut issue #63: board pakai garis tipis tanpa nomor + "Nyebrang 2 paragraf").
- **Layout ikut jumlah bagian:** 1 bagian (selesai) = tanpa nomor & judul, panel ikut ke-scroll + kalimat asli di bawah terjemahan. ≥ 2 bagian, dan selama proses / error = panel nempel di atas, tinggi = teks, maks 40% layar, lebih = scroll sendiri.
- **Penjelasan:** per bagian nomor + judul (≥ 2 bagian), MAKSUDNYA, LOGIKANYA. Lalu Tokoh & istilah (nyebut "bagian N" asal kalimatnya), Nyambung ke (kartu garis + chevron kalau tujuannya ketemu, gak ketemu = teks biasa), Praktekinnya gini (teks UI tebal 20, apa adanya, gak difilter). Blok kosong gak tampil.
- **Tombol:** Salin / status + "Balik baca" (kuning). Kepotong: Salin mati, "Balik baca" muted, kuningnya di "Coba lagi dari awal". Error: "Balik baca" + "Coba lagi" (401/403 & API key kosong: "Buka Pengaturan"; balik dari Pengaturan langsung jalan lagi). Tombol ngumpet pas scroll penjelasan (`ScrollRun`), kecuali selama proses / error / VoiceOver. **Deviasi:** header gak ikut ngumpet (board C3 / D3 header tetep keliatan, panel nempel di bawahnya).
- **State:** nunggu (placeholder bulatan + judul + baris, jumlah ditebak dari jumlah kalimat ÷ 6, gak bisa di-scroll), kelamaan (kartu di atas placeholder, Batal = balik ke Artinya), kepotong (cuma bagian yang utuh, blok penutup dibuang, banner pink), error (copy per jenis, tabel board state), dari cache (langsung jadi, dari atas).
- **Sinkron (#64, ≥ 2 bagian):** blok aktif = blok penjelasan (bagian, Tokoh & istilah, Praktekinnya gini) yang atasnya lewat garis baca 96pt dari atas area penjelasan, histeresis 24pt (`activeBlock`, `lib/domain/breakdown_sync.dart`); mentok bawah = blok terakhir. Kalimat bagian aktif disorot kuning di panel, panel scroll sendiri ke nomornya. Selama nulis sorotannya udah jalan dari bagian 1 dan ngikut scroll, gak nunggu lengkap (**deviasi dari board C2**, yang nyorot bagian yang lagi ditulis). Tap nomor di teks / chip = penjelasan lompat ke blok itu (dikunci sampe jari scroll lagi). Chip `1…n / Istilah / Praktek` cuma kalau ≥ 3 bagian, yang aktif ink, kepanjangan = geser ke samping + fade kanan. **Panel kelipet by default** di semua state (nunggu, nulis, lengkap, cache, kepotong, error, 1 bagian juga): satu baris "Teks terjemahan · n bagian" ("· 1 gagasan"; tanpa jumlah selama proses / error), soalnya terjemahannya udah dibaca di sheet Artinya. Tap baris = buka (200ms), tap kotak (selain nomor) / strip chevron di ujung bawahnya = lipet lagi, di state mana pun. Gak ada lipet / buka otomatis (chip & scroll gak ngubah lipetan), kecuali tap istilah yang ngebuka. Gak diinget antar layar. **Deviasi dari board** (C2–C6, B2: panel kebuka, ngelipet otomatis lewat bagian terakhir). Tap istilah = kata persisnya disorot (gantiin sorotan bagian), panel kebuka; istilah tanpa kata persis gak bisa di-tap. Scroll cuma ganti blok aktif, panel dibangun ulang pas aktifnya ganti doang. 1 bagian: semua mati. Kurangi gerakan: lompat & lipat tanpa animasi. VoiceOver: chip "Lompat ke bagian 2 dari 4", nomor di teks bisa di-tap; fokus belum dipindah ke heading abis lompat.
- **Intip (#65, board "Bedahin · Nyambung ke · intip"):** tap kartu = sheet intip (tinggi ikut isi, maks 70%, kepanjangan fade). Header "NYAMBUNG KE · AWAL XVII" / "LANJUTAN V · GRUP BERIKUTNYA" + judul, kalimat kenapa nyambung, kartu muted: terjemahan (kalau udah diartiin) di atas teks asli miring 15, atau teks asli ukuran Aa kalau belum. Tombol sekunder semua (gak ada kuning): "Artiin" + "Bedahin ini juga", atau "Bedahin ini juga" doang kalau udah diartiin. Artiin nge-stream `groupAiStreamProvider` grup tujuan (hasil masuk cache biasa), status di tombol Artiin, ujung memudar. **Deviasi:** tanpa ritme `Pacer`, teks muncul per token. Gagal / kepotong = baris pink di bawah kartu + "Coba artiin lagi"; key ditolak / saldo / key kosong = link "Buka Pengaturan" di barisnya. "Bedahin ini juga" sebelum diartiin = diartiin dulu (Bedahin butuh makna cepat), selesai langsung lanjut.
- **Navigasi berlapis:** "Bedahin ini juga" nutup intip dan push Bedahin grup tujuan di atas yang sekarang. Balik / swipe tepi = mundur satu lapis (posisi scroll lapis bawah tetep), "Balik baca" dari lapis mana pun nerusin `pop(true)` sampe halaman.
- **Salin:** teks polos, "buku · bab (dibedah di Luma)", per bagian nomor + judul + Maksudnya + Logikanya, Tokoh & istilah, Praktekinnya gini; tanpa terjemahan & Nyambung ke. Toast "Udah disalin, tinggal paste", tombol jadi "Disalin".
- **Kurangi gerakan:** push = fade 150ms, bagian muncul utuh, tanpa pudar. **VoiceOver:** penjelasan dibaca sebelum panel teks, tiap bagian heading "Bagian i dari n, judul", selesai diumumin "Bedahan udah lengkap, N bagian".

## Copy

Bahasa Indonesia gaya Gen Z, santai. Contoh: "Rak buku lo", "Lanjut baca yuk", "Artinya gini nih", "Maksud penulisnya tuh...", "Bentar, lagi mikir...", "Yah, gagal nih".

## Layar yang sudah didesain

Semua layar MVP awal sudah final (terang + gelap): rak kosong/berisi, baca, artinya (loading / hasil / error / udah disalin / API key kosong) dengan highlight grup, Aa, daftar isi, akhir bab, akhir buku, import (proses / berhasil / duplikat / rusak / bukan EPUB / DRM), urutkan rak, tekan lama buku, info buku, konfirmasi hapus, pengaturan, penanda grup yang sudah diterjemahkan.

## Layar yang masih didesain

Backup & restore ([backup.md](backup.md)): bagian Backup di Pengaturan, proses export, restore (pilih file → ringkasan → konfirmasi → proses → berhasil / gagal), banner pengingat backup.
