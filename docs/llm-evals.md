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
- **DeepSeek jadi default**: paling setia ke teks dan paling hati-hati soal fakta (Caius: "kemungkinan Julius Caesar atau Caligula"), makna paling kaya. Kelemahannya sedikit kaku: ditambal di prompt v4 (gaya luwes, padanan istilah yang dikenal pembaca, istilah populer seperti dikotomi kendali / amor fati dengan label jujur, satu contoh gaya). v4 dipasang tanpa evaluasi ulang atas keputusan user; dinilai lewat dogfooding (#29), ganti model tetap bisa dari Pengaturan.
- Biaya per tap sebenarnya beda dari tabel harga: GLM bukan yang termurah karena reasoning wajib.
- Glosarium per buku (mis. "power" → "kendali", "opinion" → "penilaian") masih ditunda; aturan v4 nanggung sebagian.
