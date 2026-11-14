# Integrasi LLM

## Provider

OpenRouter (API OpenAI-compatible, base URL `https://openrouter.ai/api/v1`).

Default aplikasi mengikuti `defaultAiModel` di `lib/domain/models/ai_model.dart`: GLM 5.3 Flash (sejak #200; termurah di tabel, jadi kuota gratis $0,02/hari cukup ±30–50 tap). Mode kuota gratis cuma bisa milih 3 model allowlist (`/v1/ai/config`, cadangan `subsidyModelIds`); hapus key sendiri dengan model di luar daftar itu → model balik ke default. Model live/evaluasi GLM atau Qwen pada laporan historis tidak mengubah default; pilihan tersimpan di Pengaturan tetap dipakai. Angka biaya/latensi di dokumen ini adalah snapshot evaluasi, bukan tarif atau benchmark terbaru.

## Kandidat model (harga per 1 juta token, cek ulang di OpenRouter)

| Model | Model ID | Input | Output | Catatan |
|-------|----------|-------|--------|---------|
| GLM 5.3 Flash | `z-ai/glm-5.3-flash` | $0.075 | $0.25 | Termurah di tabel, tapi reasoning gak bisa dimatiin (token output lebih banyak) dan paling sering salah ketik |
| DeepSeek V4.1 Flash | `deepseek/deepseek-v4.1-flash` | $0.15–0.30 | $0.60–1.20 | Harga beda jam sibuk / tidak sibuk. Menang evaluasi buta #28; default sekarang GLM (lihat bagian Evaluasi model) |
| Qwen 3.8 Flash | `qwen/qwen3.8-flash` | $0.15 | $0.47 | Keluarga Qwen kuat di multibahasa |

Estimasi: ~800 token input + ~400 token output per tap → dengan GLM 5.3 Flash sekitar **$0.16 per 1.000 tap**.

## Aturan implementasi

- **Model ID bisa diganti dari Pengaturan**, jangan di-hardcode.
- **Matikan reasoning** lewat parameter `reasoning` di request (token reasoning dihitung sebagai output dan bikin lambat).
- Minta output **JSON**; strip code fence sebelum `jsonDecode`.
- **Validasi** `translations.length` = jumlah paragraf grup. Kalau tidak cocok, retry sekali; kalau masih gagal, tampilkan state error.
- Timeout request ±30 detik → state error ("Yah, gagal nih"). Jalur streaming: dua tingkat, 15 detik tanpa token = "Agak lama nih..." (request tetep jalan), 30 detik = error; token berhenti 20 detik di tengah = kepotong.
- API key belum diisi → jangan panggil API, tampilkan state "API key belum diisi" dengan tombol ke Pengaturan.
- API key = `BYOK ?? key subsidi` (`AiKeyRepository`, [backend.md](backend.md), #200). BYOK = key OpenRouter sendiri di `flutter_secure_storage` (`ApiKeyStore`, field Pengaturan). Key subsidi diambil dari backend (`POST /v1/ai/key`) cuma kalau belum ada, kedaluwarsa < 1 hari, atau ditolak OpenRouter (401 → interceptor `OpenRouterService` → rotasi di baca berikutnya); disimpan di `SessionStore`, ikut terhapus saat logout. Offline: key subsidi yang belum kedaluwarsa tetap dipakai. Tanpa sesi + tanpa BYOK → `noApiKey`. Akun diblokir → `AiException(http 403, detail: AI_BANNED)`; offline tanpa key subsidi yang masih berlaku → `network`. BYOK ditolak (401) → AI berhenti, gak fallback ke kuota gratis. Tanpa proxy: AI tetap langsung device → OpenRouter.
- Kartu kuota (board "12 · Kuota AI"): `subsidyFailureOf` memetakan error mode subsidi ke `exhausted` (402) / `banned` (403 `AI_BANNED`). Sheet Artinya, Bedahin, intip, dan chat nampilin `QuotaExhaustedCard` / `QuotaBannedCard` (chat: kolom ketik dimatiin) dengan tombol "pakai key sendiri" ke Pengaturan. Meter kuota di kartu akun (`AccountQuotaMeter`, `aiQuotaProvider`, cache 1 jam); "± N tap" = sisa / `estimatedTapCostUsd` ($0,0005, konstanta sampai log biaya `ai_calls` diisi).
- Atur preferensi provider di OpenRouter kalau ingin menghindari provider yang memakai data untuk training.

**Implementasi** (`OpenRouterService`):

- `POST /chat/completions` dengan `reasoning: {"enabled": false}` dan `response_format: {"type": "json_object"}`. Timeout connect/send/receive 30 detik.
- Sebagian model gak bisa reasoning-nya dimatiin (GLM 5.3 Flash: 400 "Reasoning is mandatory..."). Kena error itu → kirim ulang sekali dengan `reasoning: {"effort": "minimal", "exclude": true}`.
- Jawaban: ambil objek JSON dari `{` pertama sampe `}` terakhir (buang code fence / basa-basi), cek `translations` = list string sejumlah paragraf TARGET dan `meaning` gak kosong. Gak valid → coba ulang sekali, masih gagal → `invalidResponse`.
- Error bertipe (`AiError`): `noApiKey` (API gak dipanggil), `timeout`, `network`, `http` (bawa status: 401 key ditolak, 402 saldo abis), `invalidResponse`. Error HTTP gak di-retry.
- API key dibaca lewat `aiKeyRepositoryProvider` tiap request (BYOK dari Keychain / Keystore; key subsidi dari storage, backend cuma kalau perlu), model dari `ai.model`.
- Key di Pengaturan (`AiSourceSection`, tab Kuota gratis / Key sendiri; ada key kesimpen = Key sendiri; `ApiKeyEntry`): spasi / baris baru dibuang pas paste. Bentuk harus `sk-or-` + huruf/angka/`-`/`_` (min 8), kalau nggak pesan merah dan gak disimpen. Bentuk bener → `GET /key` (debounce 600 ms abis ngetik): 2xx → disimpen + "Key-nya jalan · Dicek barusan"; 401/403 → gak disimpen, "ditolak OpenRouter, jadi gak disimpen"; offline/gagal → disimpen aja, cuma keterangan "disimpen aman di perangkat". Teks ngawur atau key yang ditolak gak pernah nimpa key yang udah kesimpen. Key yang udah kesimpen dicek ulang tiap Pengaturan dibuka (401/403 → "Key-nya ditolak (401)", AI berhenti sampai key diganti atau dihapus). Pemilih model mode key sendiri ambil daftar publik `GET /api/v1/models` (tanpa key, sekali per sesi app) dengan cari + chip Semua · Hemat · Konteks panjang. Tombol X di field ngosongin field dan ngehapus key dari secure storage (tanpa konfirmasi, sama kayak ngosongin field).
- **Streaming** (`explainStream`, dipakai sheet Artinya): `stream: true`, tanpa `response_format`, prompt sistem `aiStreamSystemPrompt` yang minta teks bersection, tiap penanda di baris sendiri: `[T1]` … `[Tn]`, terus `[MAKNA]`. SSE: baris `data:` dipotong per baris (baris yang kepotong di batas chunk ditahan, komentar `: OPENROUTER PROCESSING` dibuang), selesai di `data: [DONE]`. Ditutup sebelum `[DONE]` = `network`; event `{"error": ...}` di tengah = `http` dengan kodenya. Retry reasoning wajib sama kayak jalur biasa. `parseAiDraft` baca teks sebagian (teks sebelum penanda pertama dibuang, penanda kepotong di ujung ditahan); `parseAiSections` validasi akhir (penanda persis `T1..Tn, MAKNA`, gak ada yang kosong).
- **Ritme teks** (`Pacer`, pure): huruf ditampung lalu dikeluarin rata. Kecepatan = max(45 huruf/detik, buffer ÷ 1 detik), jadi ketinggalan maks ±1 detik; server selesai → sisa abis ≤ 600 ms; jawaban yang lengkap ≤ 1,5 detik sejak huruf pertama tampil langsung. Ini ganti aturan board (maks 2× baseline), lihat spike di bawah.
- **Spike streaming (#34):** hasilnya di [llm-evals.md](llm-evals.md#spike-streaming-34).
- Coba ke OpenRouter beneran: `make live` (key dari `.env` di root repo, `OPENROUTER_API_KEY=...`, di-gitignore), model lain `make live m=<model id>`. Tanpa key, test itu di-skip. Ketiga kandidat lulus (Okt 2026).

## Draft prompt

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

Hasil evaluasi prompt (#41): [llm-evals.md](llm-evals.md#evaluasi-prompt-41).

## Bedahin (#60)

Penjelasan per bagian, dipanggil manual dari akhir sheet Artinya ("Masih bingung? Bedahin"). Model sama (`ai.model`), jalur streaming sama (`breakdownStream` → `_stream` di `OpenRouterService`: SSE, retry reasoning wajib, error bertipe sama). Kode: `lib/domain/breakdown_prompt.dart`, `lib/domain/sentences.dart`.

Versi: `breakdownPromptVersion` (sekarang **1**). Naikin tiap prompt Bedahin **atau aturan `splitSentences`** berubah: rentang kalimat di cache cuma berlaku buat pemecahan yang sama.

**Kalimat bernomor** (`splitSentences`, pure): terjemahan tiap paragraf dipecah di `.` `!` `?` `…` (boleh beruntun) yang diikuti spasi + huruf besar / tanda kutip buka. Tanda kutip tutup ikut kalimat sebelumnya. Gak pecah di singkatan (`Mr.`, `Mrs.`, `Dr.`, `St.`, `dll.`, `mis.`, `dsb.`, dll.), inisial satu huruf (`J.`), angka desimal, dan penomoran di awal paragraf (`IX.`, `3.`). Nomor `K` nyambung lintas paragraf grup.

**System** (`breakdownSystemPrompt`): 1–6 BAGIAN per langkah argumen (bagian baru cuma pas keberatan / analogi baru / kesimpulan; satu gagasan atau daftar hal sejenis = 1 bagian; ragu = gabung), tiap bagian Judul / Maksudnya / Logikanya. ISTILAH (maks 5, kata persis disalin dari TERJEMAHAN), NYAMBUNG (maks 2: `LANJUT` kalau KONTEKS SESUDAH nerusin teks ini; `B<n>` cuma kalau model kenal isi bab itu, bukan nebak dari judul), PRAKTEK (cuma teks nasihat / ajaran / argumen, bukan novel / dialog). MAKSUD gak boleh diulang. Aturan ejaan + kata ganti dipake bareng prompt makna cepat (`aiSpellingRules`).

**User** (`breakdownUserPrompt(BreakdownInput)`):

```
BUKU: {judul}, {penulis}
BAB: {judul bab}
DAFTAR BAB:
[B1] {judul chapter, urut sortOrder; kosong = (tanpa judul)}
...

KONTEKS SEBELUM:
{sampe 3 paragraf sebelum grup}

TEKS ASLI:
[P1] {paragraf 1}
...

TERJEMAHAN (kalimat bernomor):
[P1]
[K1] ...
[K2] ...
[P2]
[K3] ...

MAKSUD (udah dibaca pengguna, jangan diulang/diparafrase):
{meaning dari ai_results}

KONTEKS SESUDAH (grup berikutnya di bab ini):
{teks asli grup berikutnya}
```

Terjemahan + makna dari `ai_results` grup itu. KONTEKS SEBELUM / SESUDAH kosong → bloknya gak ditulis (grup terakhir bab = gak ada Lanjutan).

**Output** (bersection, satu penanda per baris; blok opsional gak ada isinya = penandanya gak ditulis):

```
[BAGIAN K1-K3]
Judul: ...
Maksudnya: ...
Logikanya: ...
[ISTILAH]
label | kata persis di terjemahan | penjelasan
[NYAMBUNG]
B17 | judul | kenapa nyambung
LANJUT | judul | kenapa nyambung
[PRAKTEK]
...
```

**Validasi** (`parseBreakdown`, pure):

- Gagal keras → `invalidResponse` (pemanggil retry sekali, #62): gak ada `[BAGIAN]`, > 6 bagian, rentang gak mulai `K1` / bolong / tumpang tindih / lewat `Kn` / gak nutup sampe `Kn`, Maksudnya atau Logikanya kosong. `[BAGIAN K3]` = `K3-K3`.
- Dibuang per baris: baris istilah / nyambung yang kolomnya kurang dari 3; nyambung ke `B<n>` di luar daftar, `B<n>` = bab sendiri, `LANJUT` padahal gak ada grup berikutnya.
- Istilah yang kata persisnya gak ketemu di terjemahan (gak peka huruf besar) tetep ada, `exact` = null (tanpa sorot); yang ketemu dapet `sentence` (`K` pertama yang memuatnya).
- `parseBreakdownDraft` buat teks sebagian: teks sebelum penanda pertama dibuang, penanda / nama field kepotong di ujung ditahan, bagian langsung punya rentang begitu penandanya kebaca. Tanpa validasi.
- Judul bagian ditampilin UI cuma kalau bagiannya ≥ 2.

**Biaya**: Bab XXIV (±350 kata, 27 kalimat) ±3.200 token input + 770–1.250 token output, ±2× output makna cepat. DeepSeek ±$0,001–0,002 per Bedahin. Hasil eval: [llm-evals.md](llm-evals.md#bedahin-61).

`make live` ikut ngetes Bedahin (Enchiridion XXIV & V, Meditations I, Pride and Prejudice 1): makna cepat dulu, terus Bedahin, divalidasi.

## Evaluasi model

Default sekarang **GLM 5.3 Flash** (`defaultAiModel`). DeepSeek V4.1 Flash menang evaluasi buta #28 tapi bukan default. Hasil dan alasannya: [llm-evals.md](llm-evals.md#evaluasi-model-28).

## Ngobrolin buku

Chat per buku dari reader (tombol Ngobrol, aksi Tanyain ini di sheet Artinya). Model dari `ai.model` di Pengaturan, gak ada auto-switch. Gak ada web search. Kode: `lib/domain/chat_*.dart`, `lib/data/repositories/chat_*.dart`, `lib/ui/features/chat/`. Versi prompt: `chatPromptVersion` (sekarang **6**); turn menyimpan versi yang dipakai dan retry menolak versi/model yang beda dari attempt tersimpan.

Gak ada request ke provider waktu buka riwayat, restart, atau ganti Pengaturan: semua request muncul dari send / retry / Lanjutkan eksplisit. Key dibaca ulang di tiap send.

### Alur satu kiriman

1. **Planner** (`chatPlanSystem`, 1 request, `max_tokens` 600) menerima question, history, kutipan aktif, `book`, `toc` dan `readingPosition`. `toc` = tiap `chapters.id` dengan `section` induk TOC (mis. "Discourses › Book I"), `title` asli, `number` (Romawi / Arab di awal judul, supaya "bab 3" cocok dengan "III") dan `chars`. `readingPosition` = bab yang lagi dibuka reader waktu masuk chat, cuma buat menyelesaikan rujukan ("bab ini"), bukan sumber fakta. Keluarannya `strategy`, query Inggris utama + maks 3 `queries`, `chapter_ids`, `skip_ids`, `needs_clarification` + `clarification`. Rewrite pertanyaan dan pilihan strategi digabung di satu request ini, gak ada classifier terpisah.
2. Cabang menurut strategi:
   - `chapters`: pertanyaan nunjuk bab / Book / bagian. Bab yang diminta dibaca langsung.
   - `global`: butuh seluruh buku. Semua bab isi dibaca bertahap jadi catatan.
   - `specific` / `crossChapter` / `correction`: pencarian konsep di buku.
   - `offTopic`, atau `needs_clarification`: gak ada retrieval, jawaban langsung (penolakan singkat / tanya balik).
3. **Jawaban** (1 request streaming) dari sumber yang terkumpul. Sumber kosong tetap masuk ke model jawaban (buat bantuan umum atau klarifikasi).

Validasi planner (`parseChatQueryPlan`): JSON dengan key unik, `queries` ≤ 3 dan unik, strategi dikenal, `chapters` wajib bawa `chapter_ids` kecuali minta klarifikasi. ID bab (angka dalam string diterima) harus unik dan ada di `toc`; ID asing = respons invalid, tanpa request lanjutan. Aplikasi juga ngecek sendiri: kalau nomor bab ("bab III") ada di beberapa section, pertanyaan gak nyebut Book, dan posisi baca gak menentukan, model gak boleh nebak. Aplikasi menimpa rencananya jadi klarifikasi ("Maksud lo bab yang di Book I, Book II yang mana?"). Balasan pendek buat klarifikasi sebelumnya ("Book I") digabung dengan pertanyaan asalnya oleh prompt planner.

**Front/back matter.** Planner mengisi `skip_ids` (Endnotes, Imprint, Colophon, kata pengantar orang lain, …) buat `global` dan pencarian; bab isi = TOC minus `skip_ids`. `skip_ids` kosong kalau pertanyaannya justru soal bagian itu. Bab lama tanpa `section` di-backfill lokal dari EPUB tersimpan saat chat dibuka ([data-model.md](data-model.md)).

### Baca bab dan seluruh buku

Teks asli dipecah jadi window ≤ 1200 unit UTF-16 tanpa overlap, urut bab / paragraf, termasuk paragraf tanpa `groupIndex` (surrogate gak dipotong). Window dibaca dalam batch:

- Batch ≤ `chatGlobalBatchBytes` 48000 byte dan 40 window, dikecilkan mengikuti sisa context / budget. Begitu batch ≥ 60% penuh, batch berhenti di batas bab, jadi satu label per batch dan catatan rapi per bab.
- `chatGlobalConcurrency` 3 batch dikirim bersamaan (catatan per batch independen); checkpoint tetap di-commit urut cursor.
- Model cuma menulis catatan **baru** per batch (`max_tokens` 2500, termasuk reasoning GLM; GLM ±50 token/detik, jadi output per batch harus pendek): ≤ 14 catatan / 4800 karakter / 80 ID window. Aplikasi yang mengakumulasi ke checkpoint (≤ 400 catatan / 120000 karakter / 800 ID); teks bukti batch lama gak dikirim ulang, cuma catatannya (`previousNotes`).
- Catatan yang kepanjangan / terpotong / ID asing diulang **sekali per batch** dengan pesan assistant + alasan penolakan, maks `chatMaxBatchRetries` 8 per kiriman. Ini langkah baca, bukan jatah perbaikan jawaban.
- Catatan adalah ringkasan generatif yang bisa kehilangan detail, bukan kutipan dan bukan jaminan factuality. Jawaban nerima `notesAreGenerated`.

Dua prompt catatan: `chatOverviewSystem` buat `global` (catatan question-agnostic: gagasan, argumen, contoh, istilah bab) dan `chatGlobalSystem` buat `chapters` (catatan terhadap pertanyaan ini).

**Baca langsung.** Strategi `chapters` mengirim window bab yang diminta sebagai teks asli (tanpa catatan, digabung per bab, dipecah bila besar) kalau seluruhnya muat budget sumber. Kalau gak muat (bab panjang / Book utuh), diolah lewat loop catatan di atas.

**Cache catatan bab.** Strategi `global` menyimpan catatan per bab di `chat_chapter_notes` (`ChatNotesRepository`) begitu semua window bab itu selesai dibaca. Kunci: buku + revision + bab + manifest window bab + `chatChapterNotesPolicy` (1); isinya anchor paragraf, bukan ID window (ID tergantung urutan baca). Send berikutnya memuat bab yang cocok tanpa request: urutan baca menaruh bab cache di depan, `cursor` mulai dari jumlah window-nya, dan jawaban nerima `notesFromCache` (jumlah bab dari cache). Stop / Jawab sekarang di tengah tetap menyimpan bab yang sudah selesai; `contentChanged` dan hapus buku membuang cache. `chapters` tetap question-specific dan gak di-cache.

**Sumber akhir.** Window yang paling sering dikutip catatan, digabung per bab (`chatPackGlobalSources`), dipecah bila besar (`chatSplitLargeSources`), dimuat sampai budget sumber. ID catatan yang gak muat dibuang dari catatan itu, teksnya tetap. Jawaban nerima `exploration` (`scope`: `chapters | book | search`, `examinedChapters`, cakupan, `stopReason`, `clarification`).

### Pencarian konsep

Chunk: satu group paragraf ≤ 1800 unit UTF-16 = satu chunk; group lebih panjang dipecah per 1800 dengan overlap 200. Tiap putaran:

1. Embedding: dense query asli + dense tiap subquery Inggris + BM25 tiap subquery, digabung RRF (k = 60) jadi ≤ `chatMaxCandidates` 40 kandidat. Kandidat dari bab di luar bab isi dibuang setelah ranking (index embedding tetap seluruh buku). Kutipan aktif selalu ikut dan wajib tercakup utuh (multi-window / multi-group boleh); kalau gak muat, request gagal jelas, bukan dipotong. `selectedQuote` selalu teks asli, bukan terjemahan.
2. **Selector** (`chatSelectionSystem`, `max_tokens` 600, prompt ≤ `chatSelectorBytes` 90000) memilih ≤ 8 indeks kandidat dan boleh minta ≤ 2 `missing_queries` (query Inggris buat bagian yang belum terjawab). Output invalid gak di-retry.
3. Pilihan di-union lintas putaran: query lanjutan yang gak nemu apa pun gak membuang bukti sebelumnya. Di akhir, window tetangga bab yang sama ditambahkan selama masih muat.

Putaran lanjut selama selector minta `missing_queries` baru, tanpa batas putaran tetap, dengan batas: ≤ 3 query segar per putaran, ≤ 9 subquery per kiriman, ≤ 64 per rangkaian (setelah itu kirim pertanyaan baru), dan putaran baru butuh sisa jatah jawaban (lihat Budget). Pilihan identik dua putaran berturut-turut = `stagnant`. Query asli di-embed ulang tiap putaran (belum ada cache embedding query).

**Index embedding.** Qwen3 Embedding 8B (4096 dimensi) primary; fallback OpenAI `text-embedding-3-large` (3072) kalau provider timeout / network / 404 / 408 / 429 / 5xx. Auth, saldo, input invalid, cancel, sertifikat, dan error lain gak memicu fallback. Tiap model punya model-space sendiri (dokumen + query), vektor gak pernah dicampur atau dipotong. Detail:

- Vektor dokumen disimpan permanen di Drift; RAM cuma memegang satu index aktif. Kunci: versi format storage, buku / revision / parser / chunk policy / model / dimensi / query template; manifest mengikat chapter, range, hash, judul bab.
- Dibangun cuma pada send / retry eksplisit yang butuh retrieval, batch ≤ 64 dokumen, 3 batch bersamaan, disimpan atomik urut ordinal (Float32 little-endian + checksum). Putus di tengah: aksi user berikutnya lanjut dari prefix lengkap yang tersimpan; ranking baru jalan setelah semua chunk lengkap. Stop / back / background gak auto-resume. Crash setelah provider sukses sebelum commit lokal bisa mengulang biaya batch itu.
- Cache divalidasi saat load (count, ordinal, checksum, dimensi, nilai finite / bukan nol); yang rusak dibangun ulang untuk index itu saja. Perubahan isi buku menghapus indexnya; ganti judul / cover / model jawaban gak ngulang embedding. Cache ikut backup DB tapi selalu divalidasi; backup lama tanpa index tetap jalan. Gak ada API key di cache.
- Batas input: 8000 byte per input, 64 input per request, `chatEmbeddingInputBytes` 1.500.000 byte per model-space (dokumen + query); overflow ditolak sebelum request berikutnya.

### Budget, batas, dan timeout

**Ledger per kiriman** (`chat_budget.dart`), mencakup semua request chat termasuk planner, catatan, selector, perbaikan, dan jawaban:

- `chatQuestionTokens` 2.000.000 token (input + output) dan `chatQuestionDeadline` 5 menit.
- Reservasi sebelum dispatch: byte input / 2 + `max_tokens`. Usage asli dari SSE (`stream_options.include_usage`) menggantikan reservasi; usage yang gak ada tetap dihitung reservasi (gak pernah 0). Ceiling waktu dan token bukan jaminan billing.
- Context per request dari `GET /models` (`context_length`, gratis, di-cache per repository); gagal → `chatFallbackContextTokens` 128000, tercatat `contextFromProvider = false`. Margin `chatContextMargin` 4000 token buat system + overhead JSON.
- Input per request ≤ `chatRequestInputBytes` 240000 byte (menjaga latensi prompt processing di bawah tenggat), juga dibatasi context model dan sisa budget. Batch catatan, sumber, dan history mengikuti batas ini.
- Putaran baru (batch catatan atau putaran pencarian) cuma jalan kalau masih menyisakan `chatAnswerReserveTokens` 40000 token + `chatAnswerReserveTime` 45 detik buat jawaban. Kalau gak: berhenti dengan `stopReason` `budget` / `deadline`.
- Embedding dicatat terpisah: ≤ `chatEmbeddingRequests` 90 request dan `chatEmbeddingBytes` 3.200.000 byte per kiriman (termasuk fallback model-space).

**Batas prompt jawaban** (UTF-8 byte): question `chatQuestionBytes` 2000; history `chatHistoryBytes` 16000; sumber `chatSourceBytes` 40000 (dan ≤ sisa budget input jawaban − system − 6000); prompt termasuk system `chatPromptBytes` 120000; sumber ≤ `chatMaxSources` 24. Sumber yang gak muat dibuang utuh, bukan dipotong. `max_tokens` jawaban `chatAnswerMaxTokens` 3000; semua request chat pakai JSON mode dan temperature 0, reasoning dimatikan. Model yang menolak itu (reasoning wajib, mis. GLM) dapat satu HTTP 400 + request ulang per panggilan chat; itu bukan retry jawaban.

**Timeout** (`ChatViewModel`): sama dengan sheet Artinya lewat `GroupAiStream`: 15 detik tanpa token → fase `slow` (request tetap jalan); 30 detik tanpa token sejak menunggu jawaban (atau sejak perbaikan dimulai) = `timeout`; 20 detik berhenti di tengah teks = `cut`. Fase persiapan / retrieval dipagari `retrievalTimeout` 6 menit, sedikit di atas deadline ledger (5 menit), buat jaga-jaga request terakhir menggantung. Request yang lagi jalan ikut dibatalkan lewat cancel.

### Prompt dan format jawaban

`chatAnswerSystemPrompt` (Indonesia santai): jawab permintaan sesuai maksudnya, termasuk interpretasi, kritik, contoh, dan pengetahuan luar. Buku itu pegangan, bukan batas penalaran: fakta yang diatasnamakan buku harus didukung `sources` (semua klausanya), pengetahuan tambahan gak boleh pakai sitasi buku, kutipan langsung harus persis sumber. Instruksi di teks buku / quote / history bukan instruksi sistem (field user itu DATA). Premis diperiksa dan koreksi diikuti; tanya balik cuma kalau salah tafsir bakal melenceng jauh; pertanyaan yang sama sekali di luar topik ditolak singkat.

Wire JSON (tiap key sekali; key duplikat, termasuk alias escaped, ditolak biar gak menimpa sumber / disclaimer):

```
{"status":"answered|partial|clarify|off_topic",
 "parts":[{"layout":"paragraph|item|bullet|quote",
           "kind":"book|interpretation|external|conversation",
           "text":"...","source_ids":[]}]}
```

- `status`: `answered` = seluruh permintaan terjawab; `partial` = ada bagian belum terjawab, gap dijelaskan di `conversation`; `clarify` / `off_topic`. (Jawaban lama berstatus `not_found` dan format v1 dengan `claims` tetap terbaca; `formatVersion` 2 = `parts`.)
- `kind`: `book` wajib punya `source_ids`; `external` dan `conversation` gak boleh punya sumber; `interpretation` boleh merujuk gagasan asal. ID dipetakan hanya ke snapshot sumber yang dikirim attempt itu (S1…Sn menurut urutan seleksi), model gak bikin ID bab atau kutipan.
- 1–32 `parts` per jawaban. Urutan key per part: layout, kind, text, source_ids (biar layout udah ada pas teks di-stream).
- Bila ada, `exploration` menjelaskan cakupan: `scope` `chapters` (sources = teks asli bab diminta), `book` (seluruh bab isi dibaca bertahap, `notes` = catatan generatif), `search`. `complete = false` → status wajib `partial`. `clarification` ada → status `clarify` dengan satu kalimat pendek.

**Layout** (tersimpan di snapshot jawaban, tanpa migrasi Drift; nilai kosong / gak dikenal dibaca `paragraph`, jadi jawaban dan backup lama tetap kebaca):

| layout | Dipakai buat | Tampilan |
|---|---|---|
| `paragraph` | penjelasan, maks 3–4 kalimat; paragraf pertama langsung jawab | teks Aa, jarak antar blok 1em |
| `item` | 3+ hal berurutan/paralel, maks 6 berturut-turut, diawali **frasa tebal** | nomor dihitung aplikasi (Bricolage 15/700), jarak antar butir 0,5em |
| `bullet` | 3+ ciri/contoh tanpa urutan | titik 5pt, jarak sama dengan butir |
| `quote` | kutipan langsung persis sumber, cuma `kind=book`, maks 2 kalimat | blok muted radius 14 + garis kiri kuning 3pt |

Di luar `quote` + `book`, layout `quote` jatuh ke `paragraph`. Aplikasi membersihkan salah label model waktu render (data tersimpan gak diubah, `chatDisplayLayouts`): pengantar yang berakhir `:` jadi paragraf; butir pertama yang gak diawali tebal sementara semua butir sesudahnya iya = pengantar, jadi paragraf; daftar satu butir jadi paragraf; selagi streaming, blok terakhir yang pertama di daftarnya tampil paragraf dulu (nomor / titik muncul pas butir berikutnya mulai). `interpretation` dan `external` dapat label kecil (Tafsiran / Di luar buku) di awal tiap grup berturut-turut; `conversation` tampil sebagai kartu catatan muted dengan ikon info.

Inline cuma `**tebal**` dan `*miring*` (`lib/domain/chat_markup.dart`): tebal buat istilah kunci pertama kali muncul dan awal butir, 1–3 per paragraf; miring buat judul buku, kata asing, penekanan ringan. Parser toleran buat stream (penanda yang belum ketutup gak pernah tampil sebagai bintang) dan membuang markdown lain (heading, link, backtick, tanda daftar di awal). Font italic asli: Atkinson Italic + Bold Italic, Literata Italic (variable, dipakai di 400).

### Sumber, sitasi, dan validasi

- Tiap sumber punya anchor: `chapter.id`, `paragraphIndex`, offset UTF-16, hash seluruh paragraf, dan excerpt asli. Terjemahan pendamping quote bukan bukti.
- `validatePrepared` memeriksa sumber beku + owner / attempt / revision / hash live sebelum request jawaban dan sebelum chip sitasi tampil; finalize memvalidasi ulang, dan resolver sumber memvalidasi lagi saat sumber dikunjungi. Attempt yang gak aktif mengakhiri stream tanpa frame final. Hash rusak / output invalid = `AiError.invalidResponse`; SSE putus, `[DONE]` hilang, atau error provider tetap error, bukan "gak ketemu".
- Snapshot ID sah gak membuktikan semua klaim model benar; keterbatasan itu diterima dan dipantau lewat dogfooding, bukan gate kesempurnaan.
- Teks klaim dirender sebagai teks biasa: gak ada HTML, link eksternal, atau instruksi buku yang jadi aksi. Aksi sumber cuma dari objek `ChatSource` yang dipetakan aplikasi.
- **History**: turn `done`, tanpa error, ada jawaban (termasuk `partial` / `clarify` / `off_topic` dan `not_found` lama) di sesi / buku / revision aktif. Raw / interrupted / failed gak ikut. History = konteks percakapan, bukan bukti buku; jawaban utuh dipertahankan sampai `chatHistoryBytes`, yang terbaru dulu, sumber stale / corrupt ditolak.

**Perbaikan otomatis.** Output jawaban yang gagal validasi format / sumber dikirim ulang maks `chatMaxRepairs` 2 kali per kiriman dalam ledger yang sama, dengan output lama sebagai pesan assistant + alasan penolakan; gak jalan kalau tenggat habis. HTTP / saldo / key gak diulang. Draft durable hanya bertambah (output lama tetap di depan). Gagal setelah 2 perbaikan = `failed` / `invalidResponse` dengan draf yang masih terbaca + Coba lagi.

**Jawaban partial.** Kalau eksplorasi belum selesai (budget / tenggat / Jawab sekarang / stagnant), status dipaksa `partial` dan aplikasi menambah blok `conversation` berisi hitungan cakupan ("udah diperiksa n/m potongan", atau jumlah kebutuhan pencarian yang belum diperiksa) + ajakan Lanjutkan. Hitungan datang dari aplikasi, bukan model.

### Checkpoint, Lanjutkan, dan Jawab sekarang

- `chat_turns.exploration` (policy `chatExplorationPolicy` 2): book / revision / session / turn, question / model, manifest seluruh window, strategi, query, cursor / total, catatan, `chapterIds`, query searched / pending, ID terpilih, `stopReason` (`complete | budget | deadline | stagnant | user`). Di-commit setelah batch tervalidasi, di luar transaksi network; owner / attempt / phase / revision / hash diperiksa sebelum network dan sebelum commit.
- Stop / error menyimpan batch durable terakhir. Crash setelah provider sukses sebelum commit bisa mengulang biaya batch itu.
- **Lanjutkan** membuat turn baru dengan ledger baru, merebind checkpoint ke ID turn baru dalam satu transaksi, dan melanjutkan cursor / catatan / pending query durable; jawaban dan sumber turn lama tetap.
- **Jawab sekarang** (`answerNow`): loop berhenti setelah group batch yang berjalan tersimpan, `stopReason: user` ikut disimpan, jawaban `partial` dibuat dari catatan yang ada, Lanjutkan tetap tersedia.

### Langkah AI dan progres

Aplikasi mencatat jejak tiap attempt tanpa request tambahan (`ChatStep`, `lib/domain/chat_steps.dart`), disimpan sekali di `chat_turns.steps`. Jenis: `plan`, `cache`, `read`, `search`, `skip`, `repair`, `retry`, `stop`, `answer`; status `done` / `running` / `skipped`. Langkah `running` selalu paling belakang; langkah selesai dengan kind + label sama menuntaskannya. Attempt yang berakhir tanpa jawaban menandai langkah running sebagai dilewati. Batas decode: ≤ 400 langkah, label / detail ≤ 300 karakter, kind / status harus dikenal.

UI (`ChatStepsRow`): baris status setinggi 40pt di atas jawaban (titik kuning berdenyut + "Lagi baca Book II › IV: …" + "Langkah n" saat jalan; centang + "n langkah selesai" setelah selesai). Daftar langkah terbuka saat jalan, tertutup setelah selesai, toggle user menang sampai turn ganti; 6 langkah pertama tampil, sisanya bisa dibuka. Label bab "Book I › III: Judul" memakai chevron kecil, bukan karakter.

Selama baca, `prepare(onExplorationProgress:)` mengirim `{completed, total, label, notes}`: `label` = bab window pertama batch yang jalan, `notes` = catatan tersimpan di checkpoint. Catatan tampil sebagai preview provisional (blok `conversation` tanpa sumber, tag "CATATAN SEMENTARA"), bukan history terpercaya, dan bertahan sampai teks jawaban pertama masuk. Progres index embedding (chunk yang sudah durable) tampil terpisah. Tombol Jawab sekarang ada selama membaca.

### Streaming dan pacing

- `ChatStreamFrame.draft` = JSON mentah kumulatif buat checkpoint, **bukan teks UI**. Checkpoint DB tiap 500 ms / 1 KiB (complete / Stop / error / background flush ekornya); process kill bisa kehilangan ekor di bawah ambang itu.
- `ChatPreviewDecoder` membaca JSON incremental dan cuma memproyeksikan `parts[].text` ke `frame.preview` (escape / Unicode yang belum lengkap ditunda). Objek paragraf lengkap dicek dengan validator blok yang sama dengan final; ID sumber cuma dari snapshot beku dan dicek live sebelum chip tampil. Duplicate key / struktur invalid menghentikan preview dan mencabut sitasi. Hanya frame terakhir (setelah SSE DONE dan validasi final) yang punya `answer`; jawaban done mengganti preview di tempat.
- ViewModel mempublikasikan preview maks sekali per 50 ms. Bubble dan anchor paragraf dipakai ulang; scroll tetap selama respons tumbuh.
- `ChatResponse` memakai `Pacer` yang sama dengan Artinya, per attempt dan per frame, panjang dihitung per grapheme. Chip sumber menunggu seluruh teks paragraf tampil. History / cache langsung tampil; reduced motion langsung mengungkap teks aman; Stop / error / background mengungkap sisa teks tanpa menunggu drain. Final dipersist ViewModel sebelum pacing visual selesai (gak ada DB write per frame).
- Stop / network / invalid final mempertahankan teks, status terminal, dan Coba lagi eksplisit; semua sitasi provisional dicabut saat gagal / terputus. `ChatSnapshot` merekonstruksi teks draf secara defensif dari raw checkpoint saat reopen / restore, tanpa sitasi dan bukan answer / history. Legacy v1 menunggu final.

### Tampilan chat

Acuan: `design/references/ngobrolin-buku.html` (export statis; tema gelap mengikuti token Stabilo).

- Viewport penuh, header overlay `Layout.chatHeader` 52pt yang hilang saat scroll turun dan kembali saat naik (`ReaderChrome`), composer kapsul `Layout.chatComposer` 52pt minimum, tumbuh sampai lima baris. Tinggi header / composer diukur supaya teks besar dan keyboard tetap menyisakan padding scroll yang benar. Notice fitur ikut scroll.
- Jawaban pakai `readingSheet` 15,5/1,5, kolom maks `Layout.chatTextWidth` 680, paragraf berjarak 12, turn 32; bubble pertanyaan rata kanan maks `Layout.chatBubbleFraction` 82% lebar. Teks selectable. Sumber tampil sebagai chip inline (target sentuh 44), label pakai nama bab asli, bukan nomor bagian karangan dari ID aplikasi.
- Kirim menaruh pertanyaan baru di bawah header sekali dengan animasi (reduced motion = jump) dan memberi ruang tumbuh buat jawabannya. Streaming, chip, dan keyboard gak memaksa scroll. Tombol "Ke terbaru" muncul saat jarak ke bawah > `Layout.chatFollowDistance` 80pt; anchor resume / balik dari sumber tetap dipakai. Status "Lagi nulis…" live-region, teks yang tumbuh bukan; kursor visual dan titik tunggu gak diumumkan per karakter ke screen reader.
- Hanya turn terakhir yang bisa diulang / diteruskan punya aksi kecil di isi scroll (Coba lagi, Lanjutkan); status lama gak numpuk di atas composer.
- Fase `ChatPhase`: `preparing` → `retrieving` → `waiting` → `writing` (+ `slow`) → `done`; terminal gagal: `failed` (belum ada teks), `cut` (ada teks), `stopped`, `interrupted`. Perbaikan format tampil sebagai status "Lagi benerin format jawaban… (n/2)" di turn yang sama, preview lama tetap sampai teks baru masuk.
- **Sheet sumber**: viewport penuh, grabber, metadata / konteks sebelum-sesudah ikut scroll (dibaca lokal hanya buat lokasi valid), kutipan dalam blok muted, aksi Tutup + Buka di buku. Geometri mengikuti overlay Artinya dan board. Membuka sheet / reader kunjungan gak menulis progres atau waktu baca.
- **Reader kunjungan** (dari Buka di buku): cuma label intip dan kapsul Balik ke ngobrol / Lanjut baca. Label intip mengambil progres tersimpan terbaru lewat provider terpisah tanpa mereset viewport reader yang masih terbuka. Balik memulihkan anchor chat. Lanjut baca memvalidasi ulang sumber (revision, ownership, attempt, validitas teks) dan menulis posisi awal kutipan dalam satu transaksi, lalu kembali ke reader biasa di posisi baru; batal / gagal gak memindahkan progres.
- Kapsul progres reader biasa satu objek dengan tombol Ngobrol bulat di ujung. Petunjuk pertama disimpan di key `reader.chatHintSeen` (tabel `settings`).
- **Riwayat per buku**: dikelompokkan Hari ini / Kemarin / 7 hari terakhir / Lebih lama, penanda aktif / arsip, menu rename / hapus per sesi (hapus pakai konfirmasi), CTA baru di bawah. Rename sesi nonaktif gak mengaktifkan sesi itu; repository tetap memeriksa buku / revision. Sesi arsip (revision lama) gak bisa di-rename atau dilanjutkan. Draft kosong belum membuat sesi. Preview menampilkan jawaban valid terakhir, fallback ke pertanyaan.
- **Tanyain ini**: aksi di baris Artinya (Salin ikon, Tanyain ini muted, Lanjut kuning). Entry membuka composer kosong + kartu konteks dua baris yang bisa memperlihatkan kutipan + terjemahan, tanpa auto-send. Konteks pertama tampil sekali di awal history; kiriman baru menciutkan kartu. Entry kutipan yang sama melanjutkan sesi yang cocok pada buku / revision sama (pencocokan lokal, tanpa request). Nama bab opsional ikut snapshot quote JSON buat UI, kompatibel dengan snapshot lama. Terjemahan pendamping di UI bukan bukti model.

### Bukti live

- `make chat-agent-live` (`tag=`, `cases=`, `cont=`, `book=`, `m=`) menjalankan pipeline produksi pada `test/fixtures/discourses.epub` (Standard Ebooks, terjemahan Long, nav Book I–IV › bab) dan menulis `test/fixtures/book_chat_agent_<tag>.json` (jawaban, cakupan, request, usage, biaya).
- `make chat-adaptive-live` = diagnostic global + continuation pada buku sintetis 4 bab, GLM primary, `m=` buat model lain; menolak duplicate request / embedding. Gak mengukur retrieval buku nyata, billing embedding cold / warm, atau performa device.
- Mutu retrieval hybrid dan jalur Qwen terbukti dengan keterbatasan yang [diterima user](https://github.com/choiruladamm/luma/issues/113#issuecomment-6449993269); bukti spike asli diarsipkan byte-for-byte di `test/fixtures/book_chat_spike113/`. Riwayat iterasi dan hasil evaluasi: [llm-evals.md](llm-evals.md#riwayat-ngobrolin-buku).
