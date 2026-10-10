# Luma: EPUB Reader + Terjemahan & Makna per Paragraf

> Nama app: **Luma**
> Desain: **Stabilo** ([design.md](design.md))
> Status: siap eksekusi MVP
> Terakhir diupdate: Oktober 2026

> **Untuk Claude Code:** folder `docs/` adalah sumber kebenaran untuk keputusan produk, data model, dan alur. File inti ada di tabel di bawah. `docs/ideas/` adalah rencana iterasi berikutnya dan ide kasar, **jangan dikerjakan** kecuali diminta.

| File | Isi |
|------|-----|
| [design.md](design.md) | Desain Stabilo: font, warna, perilaku layar, copy |
| [data-model.md](data-model.md) | Tabel Drift, versi schema & migrasi, kunci settings |
| [grouping.md](grouping.md) | Pengelompokan paragraf jadi grup tap/AI |
| [architecture.md](architecture.md) | Routing, provider Riverpod, alur import & baca |
| [llm.md](llm.md) | OpenRouter, model, aturan implementasi, prompt, Bedahin |
| [llm-evals.md](llm-evals.md) | Hasil spike & evaluasi (#34, #41, #28, #61) |
| [backup.md](backup.md) | Backup & restore |
| [import-formats.md](import-formats.md) | Import Luma Markdown (foto buku fisik) & PDF lewat Markdown |
| [ideas/recap.md](ideas/recap.md) | Iterasi 2: Recap bacaan |
| [ideas/raw.md](ideas/raw.md) | Catatan & ide raw dari dogfooding |

---

# Latar Belakang

Alur baca saat ini:

1. Download ebook EPUB
2. Buka di app Books (iPhone)
3. Select paragraf, copy
4. Pindah ke Gemini, paste, ketik pertanyaan terjemahan + makna
5. Baca jawaban, balik ke Books, cari lagi posisi terakhir

Masalah utamanya bukan kualitas terjemahan, tapi **friksi bolak-balik antar app** yang memutus fokus baca tiap beberapa menit.

---

# Tujuan

Mengubah alur di atas menjadi **satu tap**: tap paragraf → langsung muncul terjemahan Indonesia + penjelasan makna, tanpa keluar dari halaman baca dan tanpa ngetik prompt.

## Patokan sukses MVP

- Terasa **lebih cepat dan nyaman** daripada alur Books + copy-paste ke Gemini.
- Dipakai sendiri (dogfooding) untuk baca minimal satu buku sampai selesai.

---

# Fitur MVP

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
| 9 | Backup & restore | Export semua data (buku, terjemahan, posisi baca, pengaturan) ke satu file `.zip`, simpan ke Files/AirDrop. Restore dari file itu. Pengingat kalau sudah lama belum backup. Detail di [backup.md](backup.md). |

## Di luar scope MVP (iterasi berikutnya)

Semua item di sini dan di bagian "Ditunda" tiap file docs punya issue. Label status: `status:ready` (plan jelas), `status:deferred` (nunggu pemicu, lihat "Dibuka kalau" di issue), `status:idea` (belum diputusin).

- **Recap bacaan**: terjemahan + makna semua yang sudah dibaca, plus overview "sejauh ini" → **Iterasi 2, lihat [recap.md](ideas/recap.md)** ([#104](https://github.com/choiruladamm/luma/issues/104))
- Import **Luma Markdown** + PDF lewat Markdown sudah jalan setelah MVP → lihat [import-formats.md](import-formats.md). Import PDF langsung di app direncanakan ([#83](https://github.com/choiruladamm/luma/issues/83)). Format lain (TXT, HTML, MOBI) belum ([#100](https://github.com/choiruladamm/luma/issues/100)).
- "Open in" dari app Files / share sheet ([#105](https://github.com/choiruladamm/luma/issues/105))
- Backend proxy untuk API key, wajib kalau app dirilis ke orang lain ([#106](https://github.com/choiruladamm/luma/issues/106))
- Highlight, catatan, bookmark ([#107](https://github.com/choiruladamm/luma/issues/107))
- Pilihan mode penjelasan: ringkas / detail / istilah sulit ([#108](https://github.com/choiruladamm/luma/issues/108))
- Sinkronisasi antar device ([#109](https://github.com/choiruladamm/luma/issues/109))

---

# Tech Stack

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

# Urutan Pengerjaan

1. Setup project: struktur dari Mibu, Drift, go_router, theme Stabilo (`ThemeExtension` + font asset)
2. Schema Drift: `books`, `chapters`, `paragraphs`, `reading_progress`, `ai_results`, `settings` (pakai `chapters.id` sebagai kunci, lihat [data-model.md](data-model.md))
3. `assignGroups` + unit test
4. Import EPUB: copy file, metadata, cover, parse chapter → paragraf → grup (isolate + transaksi), state import
5. Rak buku: kosong + berisi + kartu "Lanjut baca yuk" + cover default
6. Halaman baca + Daftar isi + Aa
7. Tap grup → highlight + bottom sheet (loading / hasil / error) + OpenRouter
8. Cache `ai_results`
9. Simpan & restore posisi baca + persentase
10. Pengaturan: API key, model ID, hapus cache
11. Backup & restore ([backup.md](backup.md)) + pengingat backup
12. Dogfooding, catat pain point di [raw.md](ideas/raw.md)
