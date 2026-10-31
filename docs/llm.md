# Integrasi LLM

## Provider

OpenRouter (API OpenAI-compatible, base URL `https://openrouter.ai/api/v1`).

## Kandidat model (harga per 1 juta token, cek ulang di OpenRouter)

| Model | Model ID | Input | Output | Catatan |
|-------|----------|-------|--------|---------|
| GLM 5.3 Flash | `z-ai/glm-5.3-flash` | $0.075 | $0.25 | Termurah di tabel, tapi reasoning gak bisa dimatiin (token output lebih banyak) dan paling sering salah ketik |
| DeepSeek V4.1 Flash | `deepseek/deepseek-v4.1-flash` | $0.15–0.30 | $0.60–1.20 | Harga beda jam sibuk / tidak sibuk. **Default** (evaluasi #28) |
| Qwen 3.8 Flash | `qwen/qwen3.8-flash` | $0.15 | $0.47 | Keluarga Qwen kuat di multibahasa |

Estimasi: ~800 token input + ~400 token output per tap → dengan GLM 5.3 Flash sekitar **$0.16 per 1.000 tap**.

## Aturan implementasi

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
- API key dibaca langsung dari Keychain / Keystore tiap request (bukan di-cache), model dari `ai.model`.
- Key di Pengaturan (`ApiKeyEntry`): spasi / baris baru dibuang pas paste. Bentuk harus `sk-or-` + huruf/angka/`-`/`_` (min 8), kalau nggak pesan merah dan gak disimpen. Bentuk bener → `GET /key` (debounce 600 ms abis ngetik): 2xx → disimpen + "Key-nya jalan"; 401/403 → gak disimpen, "ditolak OpenRouter, jadi gak disimpen"; offline/gagal → disimpen aja, cuma keterangan "disimpen aman di perangkat". Teks ngawur atau key yang ditolak gak pernah nimpa key yang udah kesimpen. Key yang udah kesimpen dicek ulang tiap Pengaturan dibuka (401/403 → "Key-nya ditolak OpenRouter"). Tombol X di field ngosongin field dan ngehapus key dari secure storage (tanpa konfirmasi, sama kayak ngosongin field).
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

Default **DeepSeek V4.1 Flash**. Hasil dan alasannya: [llm-evals.md](llm-evals.md#evaluasi-model-28).


## Percakapan Book Chat v2 (#137)

`chatPromptVersion = 3` (#138), format jawaban tetap v2. AI menjawab teks biasa dalam beberapa paragraf natural,
termasuk interpretasi, kritik, penerapan dan pengetahuan umum yang relevan dengan
buku. Pertanyaan sepenuhnya di luar topik buku ditolak singkat. Fakta buku harus
mengikuti sources; pengetahuan tambahan tidak diberi sitasi buku palsu. Instruksi
dalam buku/quote/history bukan instruksi sistem. Periksa premis, ikuti koreksi,
dan tanyakan klarifikasi hanya jika salah tafsir akan melenceng jauh.

Wire JSON: `status: answered | partial | clarify | off_topic`, `parts` berisi
`text`, `kind: book | interpretation | external | conversation`, dan `source_ids`.
Book wajib merujuk sumber; external/conversation tidak boleh memakai sumber buku;
interpretation boleh merujuk gagasan asal. Maksimal32paragraf, output3000token.
Semua ID harus dipetakan ke snapshot attempt yang sudah divalidasi. Key JSON
duplikat (termasuk escaped alias) ditolak agar tidak menimpa disclaimer/sumber.
Validasi struktural tidak menjamin semua klaim model benar; keterbatasan #136
masih berlaku dan ditindaklanjuti lewat dogfooding, bukan gate kesempurnaan.

Budget UTF-8 bytes: question2000, history16000, sources18000, prompt termasuk
system48000; kandidat40; selector8, snapshot akhir maksimal12 sumber dalam18000bytes. History dari turn done tanpa error pada
sesi/book/revision aktif, termasuk partial/clarify/off-topic dan legacy not_found.
History adalah konteks percakapan, bukan bukti buku; raw/interrupted/failed tidak
ikut. Jawaban utuh dipertahankan sampai budget; sumber stale/corrupt tetap ditolak.
Sesi lama dapat melanjutkan prompt terbaru tanpa menulis ulang jawaban v1. Snapshot
jawaban v2 memakai formatVersion2; v1 tetap terbaca dengan note tetap lamanya.

Tidak ada request saat buka history/restart/settings. Pada send/retry eksplisit,
no-source/ambiguity tetap dapat memanggil answer untuk bantuan atau klarifikasi;
ambiguity tidak memanggil embedding/selector. Renderer chat existing menampilkan
semua paragraf dan chip sumber yang tersedia tanpa format heading wajib.
Retrieval adaptif memakai jalur #138 di bawah. Source visit tetap #122; sumber terpilih tidak berarti seluruh buku sudah diperiksa.

Model aplikasi tetap dari Pengaturan. **Live evaluation** memakai GLM5.3Flash
primary, Qwen3.8Flash fallback sesuai instruksi user; ini tidak mengganti model
Pengaturan. Tidak ada web search atau langkah audit draf tambahan pada runtime.

## Penelusuran adaptif (#138)

Rewrite existing sekaligus memilih specific/crossChapter/global/correction/offTopic,
query utama dan maksimal3subquery Inggris. Tidak ada request classifier terpisah.
Ambiguity/off-topic melewati embedding dan selector. Spesifik/koreksi/lintas bab
memakai index durable #134, dense original + setiap subquery + BM25, RRF ke40kandidat,
selector maksimal8 dan penambahan window tetangga bab yang sama bila masih muat.
Kutipan aktif tetap wajib tercakup utuh. Selector dapat mengembalikan maksimal2
missing_queries, tanpa retry output/HTTP invalid. Awal + maksimal2putaran tambahan,
maksimal3subquery baru per kiriman. Pending query dan pilihan berhasil disimpan;
Lanjutkan mencari kebutuhan tersisa. Original question tetap di-embed bersama
subquery baru pada tiap putaran; belum ada cache embedding query. Batas keseluruhan
64subquery per rangkaian; setelah itu kirim pertanyaan baru untuk penelusuran baru.

Global tidak memakai embedding/top8sebagai proxy buku. Semua teks asli, termasuk
paragraf tanpa groupIndex, diurutkan sesuai bab/paragraf, dipecah menjadi window
tanpa overlap ≤1200UTF-16units (surrogate aman). Setiap batch ≤8window dan12000bytes
teks+metadata, maksimal3batch per kiriman. Model memperbarui catatan kumulatif
≤8catatan/1200karakter/6000bytes dengan ≤64ID window asli. Catatan adalah ringkasan
generatif yang bisa kehilangan detail, bukan kutipan atau jaminan factuality.
Bukti window digabung per chapter.id dengan range asli; overlap dideduplikasi,
gap tetap berupa anchor terpisah. Sumber akhir tetap ≤12/18000bytes; source_ids
catatan dipetakan ulang ke snapshot akhir. Batch yang melampaui kontrak/sumber
berhenti tanpa retry dan tanpa memajukan cursor, bukan memotong sitasi diam-diam.

Budget per kiriman: maksimal7completion logis termasuk answer, total ceiling
8000outputtoken,280000inputbytes kumulatif. Planner/selector600token, catatan1400,
answer3000. Maksimal70request embedding dan3200000inputbytes kumulatif termasuk
fallback model-space existing. Seluruh buku tetap dibatasi1500000bytes; batch
dokumen64. Stop mengambil putaran baru setelah100detik; pre-dispatch ceiling150detik,
ViewModel membatalkan retrieval setelah3menit. Answer memakai waiting30s/stall20s
existing. In-flight request ikut cancel/timer; ceiling waktu bukan jaminan billing.
Compatibility mandatory-reasoning existing bisa menambah satu HTTP400+fallback
per completion (maksimal14HTTP chat); bukan retry jawaban invalid atau HTTP umum.
Model aplikasi tetap dari Pengaturan, tidak auto-switch GLM/Qwen untuk mempercantik
hasil. Live harness mengirim reasoning yang didukung metadata sejak awal.

Checkpoint `chat_turns.exploration` policy1 memuat book/revision/session/turn,
question/model, manifest seluruh window, strategi/query, cursor/total/catatan atau
searched/pending/selected IDs. Commit setelah batch tervalidasi, di luar transaksi
network; owner/attempt/phase/revision/hash diperiksa sebelum network dan commit.
Lanjutkan eksplisit membuat turn baru dan rebind checkpoint ke ID baru dalam
transaksi, mempertahankan jawaban/sumber turn lama. Complete global berarti semua
window diproses, bukan setiap detail dipertahankan dalam catatan. Partial global
selalu diberi status partial serta hitungan cakupan dari aplikasi; pencarian
partial menyebut kebutuhan yang belum diperiksa. Restart/settings/hydrate tidak
mengirim request. Stop/error menyimpan batch durable terakhir; crash setelah
provider sukses sebelum commit masih bisa mengulang biaya batch itu.

`make chat-adaptive-live` adalah diagnostic produksi global+continuation pada buku
sintetis asli4bab, GLM primary; `m=qwen/qwen3.8-flash` fallback eksplisit. Guard
memakai ledger berbayar #136 tanpa menghapus reservasi lama, menolak duplicate
request/embedding pada diagnostic ini. Live tersebut tidak mengukur retrieval
buku nyata, cold/warm embedding billing, atau performa device.

## Pembacaan mandiri buku (#143)

`chatPromptVersion = 5`, checkpoint `exploration` policy 2. Planner
(`chatPlanSystem`) menerima question, history, kutipan, `book`, **`toc`** (tiap
`chapters.id` dengan `section` induk TOC, `title` asli, `number` dari Romawi/Arab,
`chars`) dan `readingPosition` dari entry reader. Keluarannya `strategy`:
`chapters` (baca bab/bagian yang dirujuk; `chapter_ids` wajib dari toc, atau
`needs_clarification` + `clarification` singkat bila "bab III" ambigu antar Book),
`global` (seluruh bab isi; front/back matter seperti Endnotes/Imprint tidak masuk
`chapter_ids`), `specific`/`crossChapter`/`correction` (pencarian konsep #138),
`offTopic`. ID bab dari model divalidasi terhadap toc; ID asing = invalid, tanpa
request lanjutan. Bab lama tanpa `section` di-backfill lokal dari EPUB tersimpan
saat chat buku dibuka ([data-model.md](data-model.md)).

`chapters`: window bab yang diminta dikirim utuh sebagai sources (teks asli, tanpa
catatan) bila muat budget sumber; bab panjang/Book utuh diolah lewat loop catatan
di bawah. `global`: loop catatan atas window bab isi berurutan. Loop catatan
(`chatGlobalSystem`): batch ≤ `chatGlobalBatchBytes` 48000 / 40 window, turun
mengikuti context model; `chatGlobalConcurrency` 3 batch dikirim bersamaan
(catatan per batch independen), checkpoint tetap commit urut cursor. Model hanya
menulis catatan **baru** per batch (≤ 14 catatan / 4800 karakter / 80 ID,
`max_tokens` 2500 termasuk reasoning GLM; GLM ≈ 50 token/detik, jadi output per
batch harus pendek; batch invalid diulang sekali, `chatMaxBatchRetries` 8 per
kiriman sebagai langkah baca, bukan jatah perbaikan jawaban), aplikasi
mengakumulasi ke checkpoint (≤ 400 catatan / 120000 karakter / 800 ID; Discourses
±24 batch × 2300 karakter);
teks bukti catatan lama tidak dikirim ulang. Catatan batch yang
kepanjangan/terpotong/ID asing diperbaiki sekali lewat pesan assistant + user
(jatah `chatMaxRepairs` bersama). Tidak ada batas putaran
tetap: berhenti saat selesai, budget/tenggat, atau cancel; `stopReason` tersimpan
(`budget | deadline | stagnant`). Pencarian: putaran lanjut selama selector minta
`missing_queries`, budget cukup, ≤ 9 subquery per kiriman dan pilihan berubah
(pilihan identik dua putaran = `stagnant`). Sumber akhir: window yang paling sering
dikutip catatan, digabung per bab (`chatPackGlobalSources`), dipecah bila besar
(`chatSplitLargeSources`), dimuat sampai budget sumber; ID catatan yang tidak muat
dibuang dari catatan itu, teksnya tetap. Jawaban menerima `exploration.scope`
(`chapters | book | search`), `examinedChapters`, cakupan, `stopReason`,
`clarification`; `complete false` tetap `partial` + trailer Lanjutkan.

**Ledger per kiriman** (`chat_budget.dart`): 2.000.000 token input+output dan 5
menit lintas semua request, termasuk perbaikan. Reservasi sebelum dispatch:
`bytes/2` input + `max_tokens`; usage asli dari SSE (`stream_options.include_usage`)
menggantikan reservasi, unknown tetap dihitung reservasi (tidak pernah 0).
Context per request dari `GET /models` (`context_length`, gratis, cache per
repository); gagal → 128000 konservatif, tercatat `contextFromProvider=false`.
Batas praktis input per request 240000 bytes. Sumber dan history jawaban dibatasi
context model (`buildChatPrompt(maxBytes:)`). Embedding dicatat terpisah (≤ 90
request / 3,2 MB per kiriman); cap buku 1,5 MB hanya untuk jalur embedding.
Putaran baru disisakan 40000 token + 45 detik untuk jawaban. Batas lama
7 completion / 3 putaran / 3 batch / 150 detik dihapus; `chatPromptBytes` 120000,
`chatSourceBytes` 40000, `chatMaxSources` 24. Lanjutkan = ledger baru, melanjutkan
cursor/catatan/pending durable. Model tetap dari Pengaturan.

**Perbaikan otomatis**: output jawaban yang gagal validasi format/sumber dikirim
ulang maksimal 2 kali per kiriman (`chatMaxRepairs`), dalam ledger yang sama,
dengan output lama sebagai pesan assistant + alasan penolakan. HTTP/saldo/kunci
tidak diulang. Draft durable hanya bertambah: output lama tetap di depan, perbaikan
ditambahkan di belakang. ViewModel menampilkan "Lagi benerin format jawaban… (n/2)"
pada turn yang sama; preview lama tetap sampai teks baru masuk. Gagal setelah 2
perbaikan = `failed/invalidResponse` dengan draf terbaca + Coba lagi.

**Progres yang ngomong (#150).** `prepare(onExplorationProgress:)` mengirim
`ChatExplorationProgress {completed, total, label, notes}`: `label` = bab window
pertama pada group batch yang sedang jalan, `notes` = catatan yang sudah tersimpan
di checkpoint. ViewModel menampilkan "Lagi baca Book II › IV: …" dan catatan sebagai
preview provisional (blok `conversation` tanpa sumber, tag "Catatan sementara"),
bukan history terpercaya; preview lama bertahan sampai teks jawaban pertama masuk.
Batch berhenti di batas bab begitu ≥ 60% kuota terisi. **Jawab sekarang**
(`answerNow`): loop berhenti setelah group yang jalan tersimpan, `stopReason: user`
ikut disimpan, jawaban `partial` dari catatan yang ada, Lanjutkan tetap tersedia.
Index embedding dokumen dikirim 3 batch bersamaan dan disimpan urut ordinal
(prefix tetap valid). **Cache catatan bab (#151).** Strategi `global` memakai `chatOverviewSystem`:
catatan per batch question-agnostic (gagasan, argumen, contoh, istilah bab) dan
disimpan per bab di `chat_chapter_notes` begitu semua window bab itu selesai
dibaca (`ChatNotesRepository`, kunci buku + revision + bab + manifest window bab +
`chatChapterNotesPolicy`; anchor paragraf, bukan ID window). Send berikutnya
memuat bab yang cocok tanpa request: urutan baca menaruh bab cache di depan,
`cursor` mulai dari jumlah window-nya, `chapterIds` checkpoint = urutan baca itu.
Jawaban menerima `notesFromCache` (jumlah bab dari cache). Stop/Jawab sekarang di
tengah tetap menyimpan bab yang sudah selesai; `contentChanged` dan hapus buku
membuang cache; strategi `chapters` tetap question-specific dan tidak di-cache.
Pencarian: planner mengisi `chapter_ids` bab isi juga untuk strategi cari; kandidat
dari bab di luar daftar (Endnotes, Imprint) dibuang setelah ranking, index embedding
tetap seluruh buku; `chapter_ids` kosong hanya kalau pertanyaannya soal bagian itu.
`chatPromptVersion = 6`.

Bukti live: `make chat-agent-live` (`tag=`, `cases=`, `cont=`, `book=`, `m=`)
menjalankan pipeline produksi pada `test/fixtures/discourses.epub` (Standard
Ebooks, terjemahan Long, nav Book I–IV › bab) dan menulis
`test/fixtures/book_chat_agent_<tag>.json` (jawaban, cakupan, request, usage,
biaya). `baseline` = pipeline sebelum #143; `v1` = hasil pertama #143. Gutenberg
hanya punya *selection* Discourses (#10661) tanpa TOC bab, tidak dipakai.

## Kontrak Book Chat v1 (arsip #114)

Bagian ini menyimpan kontrak lama untuk memahami data dan bukti spike, bukan
batas percakapan runtime v2.


`chatPromptVersion = 1` di `lib/domain/chat_prompt.dart`; system answer disalin
**identik** dari kandidat spike #113 yang diterima user. Retrieval/prompt/transport
produksi tersedia tanpa UI (#117). Model rewrite, selector, dan jawaban mengikuti
`ai.model` di Pengaturan. Bukti mutu
spike hanya untuk model/provider yang diuji, dan masih memiliki keterbatasan yang
[diterima user](https://github.com/choiruladamm/luma/issues/113#issuecomment-6449993269).

- JSON `status: answered | partial | not_found`, maksimal dua `claims` dengan
  `text` dan `source_ids`. Parser menolak status/ID tidak dikenal, duplikat, sumber
  foreign/stale, dan kontradiksi status. ID dipetakan ke snapshot sumber yang
  dikirim attempt itu; model tidak membuat chapter ID atau kutipan.
- `note` dari model selalu diganti copy tetap. Hanya claims yang berisi fakta buku;
  tidak ada blok konteks tambahan generatif. Snapshot ber-ID sah tidak membuktikan
  semua isi klaim benar. JSON parsial/draft bukan jawaban tervalidasi.
- Budget **UTF-8 bytes**, bukan token: question 2.000, history 4.000, source 18.000,
  answer prompt termasuk system 28.000; selector 90.000; kandidat 40, sumber 8,
  answer maxTokens 800. Sumber dibuang utuh bila tidak muat; kutipan pengguna wajib
  tetap tercakup seluruh rentangnya atau request ditolak jelas. Quote multi-window
  memiliki `selectedSourceIds`; `selectedQuote` selalu teks asli, bukan terjemahan.
- History hanya turn sebelum target sequence, dari session/book/revision aktif,
  phase done dan answer status answered tanpa error. Partial/not_found/cut/failed/
  stopped/interrupted tidak menjadi konteks assistant. Giliran terbaru yang utuh
  dipertahankan sampai budget, tanpa memotong jawaban. History membantu rujukan,
  tidak menjadi bukti.
- `ChatQueryPlan` memisahkan English search query dan `needsClarification` sebelum
  melihat kandidat. Ambiguitas menghasilkan no-source deterministik; bukan alasan
  menebak dari pengetahuan model. Implementasi rewrite/ranking ada di #117.
- `ChatIndexKey` memisahkan book revision/parser/chunk policy/model/query template.
  Qwen3 Embedding8B (4096) primary, OpenAI Large (3072) fallback sesuai user.
  Provider timeout/network/404/408/429/5xx dapat memicu **full** reindex dan re-embed
  semua query. Auth/billing/input/cancel/certificate tidak memicu fallback. Tidak
  mencampur/memotong vektor lintas model. Mutu hybrid baru terbukti pada Large saja.


### Retrieval dan streaming produksi (#117)

`ChatContextRepository.prepare(turn, cancel:)` membaca key dari `ApiKeyStore` pada
setiap send, mengambil turn/history/paragraf dari DB dalam snapshot transaksi,
dan menolak model/versi prompt yang berbeda dari attempt tersimpan. Caller mengambil
`model()` sebelum create/append/retry. Tidak ada network ketika hydrate history.
Tidak ada filter reading_progress: semua bab buku pada revision sesi dapat dicari.

Pipeline mengikuti spike yang diterima: group parser, window 1.800 UTF-16 dengan
overlap 200 untuk group panjang, original dense + English dense + English BM25,
RRF60 top40, selector max8. Rewrite Inggris (max256 output tokens) berjalan sebelum
kandidat; needs_clarification melewati embedding dan selector; answer tetap berjalan
untuk klarifikasi atau bantuan relevan tanpa sumber. Selector (max256) memilih indeks kandidat yang tervalidasi.
Kutipan dipertahankan utuh, termasuk multi-window/multi-group; jika tidak muat,
request gagal jelas. Source final diberi S1…S8 menurut urutan seleksi; anchor berisi
chapter.id, paragraphIndex, offset UTF-16, hash seluruh paragraf dan excerpt asli.
Teks terjemahan pendamping quote tidak dikirim sebagai bukti.

Vektor dokumen disimpan permanen di Drift lokal ([#134](https://github.com/choiruladamm/luma/issues/134)),
sementara RAM hanya memegang satu index aktif. Key memuat versi format storage,
book/revision/parser/chunk policy/model/dimensi/query template; manifest mengikat
chapter/range/hash dan judul bab. Restart atau pindah buku memuat ulang cache yang
valid, tanpa embedding dokumen ulang. Import/buka chat/history tidak mengirim request;
index dibangun hanya pada send/retry eksplisit yang memerlukan retrieval.

Batch maksimal64 disimpan atomik sebagai Float32 little-endian + checksum. Index
building dapat dilanjutkan dari prefix lengkap tersimpan pada aksi user berikutnya;
ranking baru berjalan setelah seluruh chunk lengkap. Progres UI menghitung chunk
yang sudah durable. Stop/back/background tidak auto-resume. Crash sesudah provider
sukses sebelum commit lokal tetap bisa mengulang biaya batch itu. Count, ordinal,
checksum, dimensions dan nilai finite/nonzero diperiksa saat load; cache rusak
khusus index itu dibangun ulang. Perubahan isi menghapus index buku dalam transaksi;
metadata judul/cover dan model jawaban saja tidak mengulang embedding.

Qwen4096 primary; fallback provider memakai Large3072 dengan dokumen dan query
pada model-space terpisah. Cache valid masing-masing model dipertahankan dan dapat
digunakan ulang. Auth/billing/input/cancel/certificate/unknown tidak beralih model.
Batas input embedding **1.500.000 UTF-8 bytes** per model-space (dokumen + query),
8.000 per input, batch64. Overflow ditolak sebelum request berikutnya; tidak
memotong vektor atau kutipan. Maksimal dua model-space jika fallback, bukan retry
jawaban. Cache ikut snapshot backup DB, tetapi selalu divalidasi sebelum dipakai;
backup lama tanpa index tetap bekerja. Tidak ada API key dalam cache.

Satu send normal memakai satu rewrite, embedding dokumen saat cache miss + satu
batch dua query, satu selector, dan satu answer. Warm send tanpa index ulang =
**4 request**; cold send = `ceil(chunkCount/64) + 4`, ditambah embedding dokumen Large yang belum tersimpan jika
fallback. Clarification = satu rewrite + satu answer, tanpa embedding/selector.
Sumber kosong setelah seleksi tetap masuk model jawaban. Chat max output3000,
JSON mode dan temperature0; exception
mandatory-reasoning dapat menambah satu HTTP request per panggilan chat sebelum
konten. Tidak ada retry otomatis untuk HTTP lain atau output invalid. Ini batas
request/input, bukan nominal biaya: biaya aktual bergantung model/provider; tidak
menjalankan evaluasi berbayar baru untuk port produksi ini.

`prepare` memanggil `ChatRepository.prepareSources` sebelum mengembalikan
`PreparedChat`. Null berarti attempt stale/terminal/deleted dan harus dibuang.
`PreparedChat.stream(cancel:)` hanya dapat dipakai sekali. `ChatStreamFrame.draft`
adalah JSON mentah kumulatif untuk checkpoint, **bukan teks UI**. `ChatPreviewDecoder` (#141) membaca struktur JSON incremental, hanya memproyeksikan
`parts[].text` ke `frame.preview`, menunda escape/Unicode yang belum lengkap.
Objek paragraf lengkap memakai validator blok yang sama dengan final; ID sumber
hanya dari snapshot frozen dan dicek live sebelum chip tampil. Preview tetap
provisional; hanya frame terakhir setelah SSE DONE dan validasi final memiliki
`answer`. Duplicate key/struktur invalid menghentikan preview dan mencabut sitasi;
validasi final tetap wajib untuk seluruh JSON. Tidak ada marker mentah, HTML, tautan eksternal, atau
instruksi buku yang dijadikan aksi. #120 merender teks klaim sebagai teks biasa;
action sumber hanya dari objek `ChatSource` yang dipetakan aplikasi.

`validatePrepared` memeriksa exact frozen sources + live owner/attempt/revision/hash
sebelum network jawaban dan sebelum memaparkan sitasi. Attempt yang tidak aktif
mengakhiri stream tanpa frame final; hash rusak/output invalid menjadi
`AiError.invalidResponse`. SSE putus/DONE hilang dan error provider tetap error,
bukan not_found. #118 memiliki cancel/checkpoint/finalize, termasuk error sebelum
prepare selesai. Callback harus memakai repository instance asal. Finalize memvalidasi
ulang snapshot; resolver #122 memvalidasi lagi ketika sumber dikunjungi.

Bukti historis spike tidak diubah menjadi evaluasi baru: tiga manifest original
diarsipkan byte-for-byte di `test/fixtures/book_chat_spike113/`. Manifest replay
aktif menyimpan `replayOf` + hash arsip dan hash transport produksi yang diperluas;
seluruh hash helper/prompt/gold tetap sama. Tes parity memeriksa teks/range chunk
pada kedua buku validation3, sistem prompt beku, dan integritas manifest/arsip.
Batas kualitas spike tetap berlaku; Qwen hybrid dan performa perangkat belum dibuktikan.

### Bentuk jawaban Ngobrolin buku (prompt v4)

Tiap `parts[]` punya `layout` opsional selain `kind`, `text`, `source_ids` (urutan key: layout, kind, text, source_ids, biar layout udah ada pas teks di-stream). Nilai gak dikenal / kosong dibaca `paragraph`, jadi jawaban lama dan backup lama tetap kebaca (tersimpan di snapshot jawaban, tanpa migrasi Drift).

| layout | Dipakai buat | Tampilan |
|---|---|---|
| `paragraph` | penjelasan, maks 3–4 kalimat; paragraf pertama langsung jawab | teks Aa, jarak antar blok 1em |
| `item` | 3+ hal berurutan/paralel, maks 6 berturut-turut, diawali **frasa tebal** | nomor dihitung aplikasi (Bricolage 15/700), jarak antar butir 0,5em |
| `bullet` | 3+ ciri/contoh tanpa urutan | titik 5pt, jarak sama dengan butir |
| `quote` | kutipan langsung persis sumber, cuma `kind=book`, maks 2 kalimat | blok muted radius 14 + garis kiri kuning 3pt |

Di luar `quote` + `book`, layout `quote` jatuh ke `paragraph`. Butir `item` dan `bullet` dua-duanya diawali **frasa tebal**. Dari situ aplikasi bersihin salah label model waktu render (data tersimpan gak diubah, `chatDisplayLayouts`): pengantar yang berakhir `:` jadi paragraf; butir pertama yang gak diawali tebal sementara semua butir sesudahnya iya = pengantar, jadi paragraf; daftar satu butir jadi paragraf; selagi streaming, blok terakhir yang pertama di daftarnya tampil paragraf dulu (belum tentu butir), nomor / titik muncul pas butir berikutnya mulai. `interpretation` dan `external` dapet label kecil (Tafsiran / Di luar buku) di awal tiap grup berturut-turut; `conversation` tampil sebagai kartu catatan muted dengan ikon info.

Inline cuma `**tebal**` dan `*miring*` (`lib/domain/chat_markup.dart`): tebal buat istilah kunci pertama kali muncul dan awal butir, 1–3 per paragraf; miring buat judul buku, kata asing, penekanan ringan. Parser toleran buat stream (penanda yang belum ketutup gak pernah tampil sebagai bintang) dan membuang markdown lain (heading, link, backtick, tanda daftar di awal). Font italic asli: Atkinson Italic + Bold Italic, Literata Italic (variable, dipakai di 400).

### UX streaming Ngobrolin buku (#141)

ViewModel memublikasikan preview bertanda attempt maksimal sekali per50ms, tanpa
request AI tambahan. DB tetap memakai checkpoint500ms/1KiB
existing; complete/Stop/error flush tail. Bubble dan anchor paragraf dipakai ulang,
scroll tetap selama respons tumbuh, termasuk saat user di bawah. “Ke terbaru”
adalah aksi eksplisit; kirim pertanyaan baru langsung pindah ke turn terbaru
sekali, lalu streaming tetap diam. Anchor resume/kembali sumber tetap dipakai. Status “Lagi nulis…” live-region;
teks yang tumbuh bukan live-region. Jawaban done mengganti preview di tempat.

Stop/network/invalid final mempertahankan teks, status terminal dan retry eksplisit.
Semua sitasi provisional dicabut saat terminal gagal/terputus. `ChatSnapshot`
merekonstruksi teks draf secara defensif dari raw checkpoint saat reopen/restore,
tanpa sitasi dan tanpa menjadikannya answer/history. Legacy v1 menunggu final,
tidak dipaksa memakai preview v2. Schema tetap10; process kill dapat kehilangan
tail di bawah ambang checkpoint, sedangkan stop/background menunggu flush.
Pengecekan struktur/sumber bukan jaminan semua klaim model benar.


### Pacing tampilan chat (#123)

`ChatResponse` memakai `Pacer` Terjemahin hanya untuk teks preview aman, per
attempt dan per frame pada respons aktif. Panjang dihitung dalam grapheme agar
emoji/aksen tidak terpotong. Chip sumber menunggu seluruh teks paragraf tampil;
source guards dan pencabutan sitasi saat terminal gagal tetap milik jalur #141.
History/cache langsung tampil; reduced motion langsung mengungkap teks aman.
Stop/error/background mengungkap sisa teks tanpa menunggu drain. Final tetap
dipersist oleh ViewModel sebelum pacing visual selesai; tidak ada DB write per frame.
Teks tetap selectable, paragraf berjarak token `Space.s5`, kolom maksimum
`Layout.chatTextWidth` dengan typography bacaan Stabilo dan jarak baris dark.
Output kontrak v2 tetap teks biasa; tidak ditambah renderer Markdown atau protocol baru.

### Redesign Ngobrolin Buku (#146)

Acuan screen: `design/references/ngobrolin-buku.html`. Export statis cukup untuk
implementasi; catatan naratif yang tertinggal tidak menggantikan screen dan
kontrak aplikasi. Tema gelap mengikuti token Stabilo existing.

Chat menggunakan viewport penuh dengan header overlay 52pt yang menghilang saat
scroll turun dan kembali saat naik (ReaderChrome), serta composer kapsul 52pt
minimum yang tumbuh sampai lima baris. Tinggi header/composer diukur supaya teks
besar dan keyboard tetap menyisakan padding scroll yang benar. Notice fitur ikut
scroll. Jawaban memakai readingSheet 15,5/1,5 (dark mengikuti forBrightness),
paragraf berjarak12, turn32; bubble pertanyaan rata kanan maksimal82% lebar.
Sumber tampil sebagai chip inline dengan target sentuh44. Label memakai nama bab
asli yang tersedia, tidak mengarang nomor bagian dari ID aplikasi.

Kirim menempatkan pertanyaan baru di bawah header sekali dengan animasi; reduced
motion memakai jump. Turn terbaru diberi ruang minimum untuk pertumbuhan jawaban.
Streaming/final, munculnya chip dan keyboard tidak memaksa scroll. Tombol turun
muncul saat jarak ke bawah lebih80pt. Pacing/source guards tetap memakai #123/#141;
kursor visual dan titik tunggu tidak mengumumkan setiap karakter ke screen reader.
Hanya turn terakhir yang dapat diulang/diteruskan memiliki aksi kecil dalam isi
scroll; status lama tidak menumpuk tombol di atas composer. Settings, error dan
Lanjutkan tetap memakai state ViewModel existing.

Sheet sitasi memiliki viewport penuh, grabber, metadata/konteks yang ikut scroll,
kutipan dalam blok muted, serta close dan Buka di buku satu baris di bawah.
Geometri mengikuti overlay Artinya: isi margin24, grabber atas10, tombol bawah34,
fade atas20 clear12; fade bawah20 clear86; padding akhir102. Sesuai screen #146,
teks kutipan mulai pada margin24, latar kutipan melebar 12 di kedua sisi dan
padding vertikal10; aksi bawah memakai margin16 dan jarak10. Konteks sebelum/sesudah
serta label posisi dibaca lokal hanya untuk lokasi valid. Membuka sheet/reader
kunjungan tetap tanpa penulisan progres maupun waktu baca.

Reader kunjungan hanya memiliki label intip dan kapsul Balik ke ngobrol / Lanjut
baca. Label intip mengambil progres tersimpan terbaru lewat provider terpisah,
tanpa mereset viewport reader yang masih terbuka di belakang. Balik memulihkan
anchor chat. Lanjut baca memvalidasi ulang sumber dan menulis
posisi awal kutipan dalam satu transaksi; kemudian kembali ke reader biasa di
posisi baru. Revision, ownership, attempt dan validitas teks harus tetap cocok.
Pembatalan/kegagalan tidak memindahkan progres. Reader asli memuat posisi tersimpan
sebelum melanjutkan clock; posisi lamanya tidak boleh menimpa hasil aksi eksplisit.
Kapsul progres reader biasa kini satu objek dengan tombol Ngobrol bulat di ujung. Petunjuk pertama disimpan sebagai key `reader.chatHintSeen` pada settings; tidak ada perubahan schema.

Riwayat per buku dikelompokkan Hari ini/Kemarin/7 hari terakhir/Lebih lama, memiliki
penanda aktif/arsip, menu rename/hapus per sesi dan CTA baru di bawah. Rename sesi
nonaktif tidak mengaktifkan sesi itu; repository tetap memeriksa buku/revision.
Arsip tidak bisa diubah judulnya/dilanjutkan; hapus tetap membutuhkan konfirmasi.
Draft kosong belum membuat sesi. Preview menampilkan jawaban valid terakhir; fallback pertanyaan ketika belum tersedia.

Tanyain ini berada pada baris aksi Artinya: Salin ikon, Tanyain ini muted, Lanjut
kuning. Isi sheet lain tidak didesain ulang. Entry membuka composer kosong dan
kartu konteks ciut (dua baris) yang bisa memperlihatkan kutipan + terjemahan, tanpa
auto-send. Konteks pertama tampil sekali di awal history; kiriman baru menciutkan
kartu. Baca di buku membuka kunjungan tervalidasi, progres baru pindah pada Lanjut
baca. Header menyediakan kembali satu lapis dan akses ringkas langsung Balik baca.
Entry kutipan yang sama melanjutkan sesi yang cocok pada buku/revision sama;
pencocokan lokal tidak mengirim request AI. Nama bab opsional ikut snapshot quote
JSON untuk UI, kompatibel dengan snapshot lama tanpa perubahan schema. Terjemahan
pendamping UI tetap bukan bukti model. Import/hydrate/history tidak menambah paid
request. #143 tetap menangani kualitas konteks/retrieval, bukan redesign ini.
