# Hasil evaluasi LLM

Data historis di balik keputusan di [llm.md](llm.md). Urut waktu.

## Spike streaming (#34)

Okt 2026. 10 grup Pride and Prejudice (5 dialog 3–6 paragraf, 5 paragraf panjang 660–1080 huruf) × 3 model:

| Model | Bersection valid | JSON valid | Token pertama (median / maks) | Total (median) | Alir huruf/detik (median, min–maks) |
|-------|-----|-----|-----|-----|-----|
| GLM 5.3 Flash | 10/10 | 9/10 | 0,96 / 2,7 dtk | 7,0 dtk | 219 (142–487) |
| DeepSeek V4.1 Flash | 10/10 | 10/10 | 1,36 / 2,2 dtk | 4,7 dtk | 428 (90–1030) |
| Qwen 3.8 Flash | 10/10 | 10/10 | 0,82 / 2,0 dtk | 6,7 dtk | 230 (199–263) |

Token pertama 4–7× lebih cepat dari jawaban lengkap: streaming kerasa. Format bersection dipilih (lebih stabil, teks sebagian gampang diambil; penanda bisa diperluas buat nomor kalimat #36, mis. `[T1 K3-4]`). Simulasi ritme dari jadwal token asli: aturan board ketinggalan median 2,2–3,8 dtk (maks 5,4) lalu loncat pas selesai; aturan adaptif maks 1,8 dtk. Adaptif dipakai.

## Evaluasi prompt (#41)

Okt 2026. 50 potong asli (25 The Enchiridion bab I–LI, 25 Meditations buku I–XII, Gutenberg #45109 dan #2680; panjang 101–4175 huruf, 4 grup multi-paragraf), GLM 5.3 Flash, jalur streaming:

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

## Evaluasi model (#28)

Okt 2026. Set 50 potong #41, prompt v3, jalur streaming, penilaian buta (A/B/C diacak per potong):

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
- **DeepSeek jadi default** (saat itu; default belakangan pindah ke GLM, lihat `docs/llm.md`): paling setia ke teks dan paling hati-hati soal fakta (Caius: "kemungkinan Julius Caesar atau Caligula"), makna paling kaya. Kelemahannya sedikit kaku: ditambal di prompt v4 (gaya luwes, padanan istilah yang dikenal pembaca, istilah populer seperti dikotomi kendali / amor fati dengan label jujur, satu contoh gaya). v4 dipasang tanpa evaluasi ulang atas keputusan user; dinilai lewat dogfooding (#29), ganti model tetap bisa dari Pengaturan.
- Biaya per tap sebenarnya beda dari tabel harga: GLM bukan yang termurah karena reasoning wajib.
- Glosarium per buku (mis. "power" → "kendali", "opinion" → "penilaian") masih ditunda; aturan v4 nanggung sebagian.

## Bedahin (#61)

Okt 2026. Pertanyaan utama: bisa gak model balikin rentang kalimat (`K1-K3`) yang valid dengan konsisten. 4 teks × 3 run, terjemahan + makna dari DeepSeek (sama buat semua model), jalur non-streaming biar `usage` kebaca. Qwen 3.8 Flash gak dievaluasi: provider-nya (Alibaba) sering 429 / rate-limited.

| | DeepSeek V4.1 Flash | GLM 5.3 Flash |
|---|---|---|
| Rentang valid (v2 + v3) | 24/24 | 23/24 (1× `K4-K7` dari 5 kalimat) |
| XXIV (harapan 4 bagian) | 4, 4, 4 | 4, 4, 4 |
| V (harapan 1) | 2, 2, 2 | 2, 4, 3 |
| Meditations I (harapan 1 + `LANJUT`) | 2, 1, 4; `LANJUT` 3/3 | 1, 1, 1; `LANJUT` 3/3 |
| Pride and Prejudice (naratif, harapan tanpa Praktek) | Praktek 1/3 | Praktek 2/3 |
| Token output XXIV | 771–948 | 965–1.254 |
| Waktu XXIV (total) | 2,6–3,3 dtk | 42–66 dtk |
| Biaya XXIV | $0,0010–0,0018 | $0,0017–0,0022 |

- **Rentang kalimat jalan**: desain Opsi C (nomor bagian, sorotan sinkron) aman, gak perlu fallback "model nulis kalimat awal aja".
- XXIV dibagi persis per putaran debat (K1-6 takut jadi bukan siapa-siapa, K7-15 teman, K16-24 negara, K25-27 kesimpulan) di hampir semua run.
- **v1 → v2**: v1 ngarang isi bab dari judul yang cuma angka romawi (Nyambung ke "Bab VIII" dengan isi yang salah), gak pernah nulis `LANJUT`, Meditations dipecah per kalimat, istilah kadang nyalin kata Inggris. v2: daftar sejenis = 1 bagian, `LANJUT` eksplisit, `B<n>` cuma kalau kenal isinya, kata persis wajib dari terjemahan. Hasilnya `LANJUT` 12/12 di grup yang punya lanjutan, Nyambung ke bab lain jarang (2/24) dan masuk akal.
- **v2 → v3**: Praktek dipaksain ke novel (5/6 run) → v3 batasin ke teks nasihat / ajaran / argumen. Turun jadi 3/6, belum beres; dinilai lewat dogfooding (#29).
- V tetep 2 bagian (penilaian vs kejadian, lalu tiga tahap menyalahkan). Bisa diterima: tampilan 2 bagian di desain (nomor, tanpa chip).
- GLM lambat buat Bedahin (reasoning wajib, 40–66 dtk teks panjang) dan bagiannya lebih gampang kepecah. DeepSeek tetep default saat itu (belakangan default pindah ke GLM, lihat `docs/llm.md`).


## Pembekuan ulang guard (13 November 2026)

Guard hash evaluasi chat (`test/fixtures/book_chat_heldout_protocol_v1.json`, `book_chat_validation2_protocol.json`, `book_chat_validation3_protocol.json`, dan hash `pubspec.lock` ternormalisasi di `test/l10n_test.dart`) dibekukan ulang untuk dua file. Prompt, retrieval, parser, dan pemilihan model gak berubah:

- `lib/data/services/openrouter_service.dart` (#200): constructor dapat callback opsional `onKeyRejected` + interceptor Dio yang melapor 401 (rotasi key subsidi), dan provider memakai `AiKeyRepository`. Request/response ke OpenRouter tetap sama.
- `pubspec.lock` (#211): tambah `url_launcher` (link Kebijakan privasi di layar Masuk). Dependency runtime AI gak berubah.
- `pubspec.lock` (#211, 14 November 2026): tambah `google_sign_in` 7.2.0 + paket platformnya (`_android`, `_ios`, `_web`, `_platform_interface`, `google_identity_services_web`) buat login Google. Hash `pubspec.lock` di `l10n_test.dart` dan di tiga protocol (heldout, validation2, validation3) dibekukan ulang; dependency runtime AI gak berubah.
- `lib/domain/luma_markdown.dart` (14 November 2026, protocol heldout): cuma komentar rujukan docs yang dibenerin (`docs/ideas/import-formats.md` → `docs/import-formats.md`), parser gak berubah.

File hasil evaluasi lama (`*_result*.json`) sengaja gak disentuh: isinya catatan historis dari versi saat evaluasi dijalankan. Menambah dependency berikutnya butuh pembekuan ulang yang sama dan baris baru di sini.

## Riwayat Ngobrolin buku

Iterasi chat yang membentuk perilaku di [llm.md](llm.md#ngobrolin-buku). Angka tiap iterasi sudah diganti yang sekarang di sana; di sini cuma apa yang berubah dan kenapa.

- **Spike (#113, #114):** kontrak v1 (`answered | partial | not_found`, maks 2 klaim berisi fakta buku saja, history cuma jawaban `answered`, rewrite + selector terpisah). Hybrid dense + BM25 + RRF dan selector terbukti pada Large; Qwen hybrid dan performa device gak dibuktikan. Manifest spike diarsipkan di `test/fixtures/book_chat_spike113/`, guard hash di bagian Pembekuan ulang guard.
- **Retrieval dan streaming produksi (#117, #134):** port pipeline spike ke aplikasi, index embedding permanen di Drift supaya restart gak embedding ulang, fallback model embedding per model-space.
- **Pacing dan preview (#123, #141):** teks chat memakai `Pacer` Artinya; preview diproyeksikan dari JSON streaming supaya jawaban kebaca selagi ditulis, sitasi dicabut kalau gagal.
- **Kontrak v2 (#137):** jawaban jadi paragraf natural bertipe (`book | interpretation | external | conversation`) dengan status `clarify` / `off_topic`, supaya interpretasi, kritik, dan pengetahuan luar boleh tanpa dipaksa jadi sitasi buku. v1 tetap terbaca.
- **Bentuk jawaban (prompt v4):** `layout` (paragraph / item / bullet / quote) + inline tebal / miring, supaya jawaban panjang gampang dipindai; nilai gak dikenal jatuh ke `paragraph`.
- **Penelusuran adaptif (#138):** rewrite + strategi (specific / crossChapter / global / correction / offTopic) dalam satu request, `missing_queries` dari selector, mode global dengan catatan kumulatif. Dulu dibatasi 7 completion, 3 putaran, 3 batch, 150 detik per kiriman.
- **Pembacaan mandiri buku (#143):** planner membaca TOC asli (`chapters.section`, nomor bab) dan memilih baca bab / seluruh buku / pencarian; ledger token + waktu per kiriman menggantikan batas tetap (completion, putaran, batch); batch paralel, perbaikan otomatis jawaban invalid (maks 2), prompt v5. Alasan: pertanyaan "bab III" dan "ringkas buku ini" gak terjawab oleh pencarian konsep. Hasil run: `test/fixtures/book_chat_agent_<tag>.json` (`baseline` = pipeline sebelum #143, `v1` = hasil pertama).
- **Progres yang ngomong (#150):** label bab yang lagi dibaca, catatan sementara, Jawab sekarang (`stopReason: user`), index embedding 3 batch bersamaan.
- **Cache catatan bab (#151) dan front/back matter:** catatan `global` question-agnostic disimpan per bab; `skip_ids` dari planner mengeluarkan Endnotes / Imprint; pilihan selector di-union lintas putaran; prompt v6.
- **Langkah AI:** jejak per attempt (rencana, baca, cari, berhenti, perbaikan) disimpan di `chat_turns.steps` dan ditampilkan sebagai baris status di atas jawaban.
- **Redesign (#146):** viewport penuh, header overlay, composer kapsul, sheet sumber, reader kunjungan, riwayat per sesi, Tanyain ini.
