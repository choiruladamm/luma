# Iterasi 2: Recap Bacaan

## Tujuan

Misal sudah baca 18% buku. Pengguna bisa membuka layar Recap untuk:

1. Melihat **terjemahan + makna semua paragraf** dari awal sampai posisi baca sekarang, dikelompokkan per chapter.
2. Membaca **overview "sejauh ini"**: ringkasan keseluruhan bagian yang sudah dibaca.

Berguna untuk baca sekilas ulang tanpa harus tap paragraf satu per satu.

## Prinsip

- **Bebas spoiler**: tidak pernah memproses teks setelah posisi baca terakhir.
- **Reuse cache**: hasil disimpan ke `ai_results` yang sama dengan fitur tap, **per grup**. Grup yang diproses lewat Recap langsung instan saat di-tap di reader, dan sebaliknya.
- **Unit = grup** ([grouping.md](../grouping.md)), bukan paragraf tunggal.
- **Per chapter, bukan per halaman**: EPUB bersifat reflowable, jumlah "halaman" berubah tergantung ukuran font dan layar. Chapter adalah unit yang stabil.
- **Persentase** dihitung dari posisi paragraf (atau jumlah karakter) terhadap total buku.

## Bagian A: Terjemahan + makna semua yang sudah dibaca

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

## Bagian B: Overview "sejauh ini"

Pakai **ringkasan bertingkat**, jangan kirim seluruh teks yang sudah dibaca setiap kali:

1. **Chapter selesai dibaca** → buat ringkasan chapter sekali, simpan.
2. **Chapter yang sedang dibaca** → buat ringkasan sampai paragraf terakhir yang dibaca. Update kalau posisi baca sudah maju cukup jauh.
3. **Overview keseluruhan** → dibuat dari gabungan ringkasan chapter, bukan dari teks mentah.

Hasilnya lebih murah, lebih cepat, dan otomatis bebas spoiler.

## Tambahan data model

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

## Layar Recap

- **Atas**: kartu overview "Sejauh ini (18%)"
- **Bawah**: daftar chapter (expand/collapse), masing-masing dengan ringkasan chapter
- **Saat chapter dibuka**: paragraf dengan terjemahan + makna
- **Toggle tampilan**: terjemahan saja / makna saja / berdampingan dengan teks asli
- **Tap paragraf** → lompat ke posisi tersebut di reader
- **Progress bar** saat job berjalan, misal "45 / 120 bagian"

## Catatan implementasi

- Job pengisian dibuat sebagai Riverpod `Notifier` yang menyimpan state progres (total grup, selesai, gagal).
- Batasi **3–5 request paralel**, pakai retry dengan backoff, dan sediakan tombol batal.
- iOS akan menghentikan proses saat app ditutup atau masuk background. Karena hasil disimpan per paragraf, job cukup **melanjutkan yang belum selesai** saat app dibuka lagi.
- Pakai endpoint OpenRouter **standar**, bukan varian `:batch`. Untuk GLM 5.3 Flash, varian batch justru lebih mahal (per Oktober 2026).
- Opsional: **prefetch** beberapa paragraf ke depan di background saat membaca, supaya tap terasa instan dan Recap makin lengkap.

## Estimasi biaya

Buku rata-rata sekitar 100 ribuan token teks. Dengan GLM 5.3 Flash, terjemahan + makna **satu buku penuh** kira-kira **~$0.10**. Recap 18% hanya beberapa sen. Tantangan utama ada di UX dan kecepatan, bukan biaya.

## Urutan pengerjaan Iterasi 2

1. Job pengisian grup yang belum diterjemahkan (chunk + progress + retry)
2. Layar Recap: daftar chapter + paragraf + toggle tampilan
3. Ringkasan per chapter (`chapter_summaries`)
4. Overview keseluruhan (`book_overviews`)
5. Lompat dari Recap ke posisi di reader
