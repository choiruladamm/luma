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
- API key dibaca langsung dari Keychain tiap request (bukan di-cache), model dari `ai.model`.
- Key di Pengaturan (`ApiKeyEntry`): spasi / baris baru dibuang pas paste. Bentuk harus `sk-or-` + huruf/angka/`-`/`_` (min 8), kalau nggak pesan merah dan gak disimpen. Bentuk bener → `GET /key` (debounce 600 ms abis ngetik): 2xx → disimpen + "Key-nya jalan"; 401/403 → gak disimpen, "ditolak OpenRouter, jadi gak disimpen"; offline/gagal → disimpen aja, cuma keterangan Keychain. Teks ngawur atau key yang ditolak gak pernah nimpa key yang udah kesimpen. Key yang udah kesimpen dicek ulang tiap Pengaturan dibuka (401/403 → "Key-nya ditolak OpenRouter"). Tombol X di field ngosongin field dan ngehapus key dari Keychain (tanpa konfirmasi, sama kayak ngosongin field).
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

## Evaluasi model

Default **DeepSeek V4.1 Flash**. Hasil dan alasannya: [llm-evals.md](llm-evals.md#evaluasi-model-28).
