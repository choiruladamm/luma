# Ide Kasar: Import Luma Markdown, Foto Buku Fisik & Format Lain

> Status: ide kasar, belum final. Kandidat **Iterasi 3**. Yang sudah diambil ke MVP hanya keputusan skema (ID chapter stabil + `sourceType` + `bookKey`, [data-model.md](../data-model.md)).

## Konsep umum

Format internal (**buku → chapter → paragraf → grup**) sudah dipakai di MVP untuk EPUB. Format lain cukup ditambah sebagai **importer baru** yang menghasilkan struktur yang sama. Reader, tap terjemahan, cache, dan Recap tidak perlu diubah.

```
EPUB ─────────┐
Luma Markdown ┼─► Importer ─► chapters + paragraphs + groups (Drift) ─► Reader / AI / Recap
PDF (nanti) ──┤
TXT (nanti) ──┘
```

## Skenario utama: baca buku fisik per chapter

Contoh: lagi baca Atomic Habits versi fisik.

1. Foto semua halaman chapter 3 (misal 10 foto)
2. **Di luar Luma**: kirim foto ke LLM (chat Claude/Gemini, atau nanti script) dengan prompt template di bawah → hasil file `.md` format Luma Markdown
3. Import `.md` ke Luma → buku "Atomic Habits" baru muncul di rak dengan satu chapter
4. Minggu depan lanjut chapter 7: foto → convert di luar → import `.md` → **otomatis masuk ke buku Atomic Habits yang sama**, terurut setelah chapter 3

Pembagian kerja: semua urusan foto, OCR, dan konversi ada **di luar app**. Luma hanya tahu cara import file Markdown yang sudah jadi.

## Format Luma Markdown (v1)

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

## Logika import di Luma

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

## Prompt template konversi foto (dipakai di luar app)

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

## Opsi support PDF

| Jalur | Cara | Kelebihan | Kekurangan |
|-------|------|-----------|------------|
| 1. Convert di luar app | Marker / Docling (PDF → Markdown) lalu sesuaikan ke format Luma Markdown, atau Calibre (PDF → EPUB) | Nol kode tambahan, cocok untuk sekarang | Manual, hasil Calibre sering berantakan |
| 2. Parse di app | `pdfrx` ekstrak teks + heuristik (sambung baris, hapus hyphen, buang header/footer, deteksi paragraf dari jarak/indentasi) | Langsung dari HP | Banyak trial-error, tiap PDF bisa beda |
| 3. Parse dengan LLM | Kirim teks atau gambar halaman ke LLM, minta JSON paragraf | Bisa handle PDF scan, hasil rapi | Risiko teks berubah dari aslinya, perlu instruksi tegas |

Setelah importer Luma Markdown ada, jalur 1 jadi jalur default untuk PDF: PDF → Markdown di luar app → import.

## Format lain yang mungkin disupport

- **TXT**: paling gampang
- **HTML**: relatif mudah (EPUB pada dasarnya HTML)
- **MOBI / AZW3**: convert ke EPUB via Calibre dulu
- File dengan **DRM** tidak bisa diparse

## Urutan pengerjaan kasar (Iterasi 3)

1. Parser frontmatter + body Luma Markdown + unit test
2. Logika import: buku baru / tambah chapter / chapter duplikat
3. Sisip chapter + hitung ulang `sortOrder` & `charOffset`
4. UI: import `.md`, dialog tanpa frontmatter, dialog ganti chapter, toast
5. Daftar isi dengan bab bolong + progres per chapter
6. (Opsional) Script konversi foto → `.md` via OpenRouter
