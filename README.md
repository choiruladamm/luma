<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="apps/mobile/assets/brand/wordmark-white.png">
    <img src="apps/mobile/assets/brand/wordmark.png" alt="Luma" height="72">
  </picture>
</p>

<p align="center">
  EPUB reader untuk iOS. Tap satu paragraf, langsung muncul terjemahan Indonesia dan maknanya, tanpa keluar dari halaman baca.
</p>

<div align="center">
<table>
  <tr>
    <td align="center">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="docs/images/rak-dark.png">
      <img src="docs/images/rak.png" alt="Rak buku" width="250">
    </picture>
    </td>
    <td align="center">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="docs/images/arti-dark.png">
      <img src="docs/images/arti.png" alt="Sheet terjemahan dan makna" width="250">
    </picture>
    </td>
    <td align="center">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="docs/images/bedahin-dark.png">
      <img src="docs/images/bedahin.png" alt="Layar Bedahin" width="250">
    </picture>
    </td>
  </tr>
</table>
</div>

## Kenapa ada

Baca buku bahasa Inggris di app Books itu enak, sampai ketemu paragraf yang gak nyantol: select teks, copy, pindah ke app LLM, paste, ketik "artiin dong", baca, balik, cari lagi posisi terakhir. Terjemahannya bagus, tapi alurnya mutus fokus baca tiap beberapa menit.

Luma ngubah alur itu jadi **satu tap**.

## Fitur

- **Tap paragraf → terjemahan + makna.** Seluruh grup paragraf distabilo dan dikirim ke LLM; hasilnya muncul di bottom sheet, ditulis bertahap (streaming).
- **Bedahin.** Masih bingung sama maknanya? Layar sendiri yang ngebedah gagasan jadi beberapa bagian, lengkap dengan sambungan ke bagian lain di buku.
- **Cache hasil AI.** Grup yang udah pernah di-tap gak manggil LLM lagi.
- **Import EPUB.** Parser sendiri (container → OPF → spine → TOC → cover), jalan di isolate. TOC rusak dilewatin, bukan bikin import gagal.
- **Rak buku** dengan cover, progres, dan kartu "Lanjut baca yuk".
- **Halaman baca imersif.** Cuma teks dan garis progres tipis; menu muncul sebagai kapsul ngambang. Pengaturan Aa (font, ukuran, jarak baris, tema terang/gelap).
- **Posisi baca tersimpan** per buku.
- **Backup & restore** semua data ke satu file `.zip`.

Data semuanya lokal di device (SQLite lewat Drift). Satu-satunya yang keluar adalah teks grup yang lagi di-tap, dikirim ke OpenRouter pakai API key milik sendiri.

## Desain

Desain sistemnya namanya **Stabilo**: teks dulu, UI belakangan. Kuning stabilo cuma buat yang lagi penting (satu layar, satu tombol kuning), dan mode gelap pakai hitam hangat, bukan hitam pekat. Semua layar punya versi terang dan gelap. Spek lengkapnya ada di [docs/design.md](docs/design.md).

<table>
  <tr>
    <td align="center">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="docs/images/baca-dark.png">
      <img src="docs/images/baca.png" alt="Halaman baca imersif" width="250">
    </picture>
    </td>
    <td align="center">
    <img src="docs/images/arti-stream.png" alt="Sheet Artinya saat streaming" width="250">
    </td>
    <td align="center">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="docs/images/aa-dark.png">
      <img src="docs/images/aa.png" alt="Pengaturan bacaan Aa" width="250">
    </picture>
    </td>
    <td align="center">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="docs/images/bedahin-nyambung-dark.png">
      <img src="docs/images/bedahin-nyambung.png" alt="Bedahin dengan sambungan antar bagian" width="250">
    </picture>
    </td>
  </tr>
</table>

<details>
<summary>Foundation: warna, tipografi, komponen</summary>

<img src="docs/images/warna.png" alt="Token warna Stabilo, terang dan gelap">
<img src="docs/images/tipografi.png" alt="Tipografi: Bricolage Grotesque, Atkinson Hyperlegible, Literata">
<img src="docs/images/komponen.png" alt="Komponen dasar">

</details>

## Tech stack

| | |
|---|---|
| UI | Flutter (versi dikunci lewat [FVM](https://fvm.app), `.fvmrc`) |
| State | Riverpod 3 |
| Database | Drift |
| Routing | go_router |
| LLM | [OpenRouter](https://openrouter.ai), model bisa diganti dari Pengaturan |
| API key | `flutter_secure_storage` (Keychain), gak ikut backup |
| Model data | freezed |

## Struktur repo

```
apps/mobile/   app Flutter
docs/          produk, data model, arsitektur, LLM, backup
```

Arsitektur berlapis (UI → data) di `apps/mobile/lib`:

```
data/        database Drift, service (OpenRouter, file, secure storage), repository
domain/      logika pure (grouping, parser) + model immutable
routing/     go_router
ui/          tema Stabilo, widget shared, fitur per folder (views + view_models)
```

## Dokumentasi

Mulai dari [docs/README.md](docs/README.md). Isinya latar belakang, keputusan produk, dan indeks ke:

| | |
|---|---|
| [design.md](docs/design.md) | Desain Stabilo: font, warna, perilaku layar |
| [data-model.md](docs/data-model.md) | Tabel Drift, schema, migrasi |
| [grouping.md](docs/grouping.md) | Cara paragraf dikelompokin jadi grup tap |
| [architecture.md](docs/architecture.md) | Routing, provider, alur import & baca |
| [llm.md](docs/llm.md) | OpenRouter, prompt, streaming, Bedahin |
| [llm-evals.md](docs/llm-evals.md) | Hasil evaluasi model |
| [backup.md](docs/backup.md) | Backup & restore |

## Menjalankan

Butuh Flutter lewat [FVM](https://fvm.app), Xcode, dan iPhone atau simulator iOS.

```bash
make get        # pub get
make gen        # codegen (drift, freezed)
make check      # format, analyze, test
make run        # debug di device / simulator
make help       # daftar semua perintah
```

Buat pakai fitur AI, isi API key OpenRouter di **Pengaturan** (key diawali `sk-or-`).

`make release` dan `make dev` meng-install build release ke iPhone yang tersambung. Ada dua app terpisah (bundle id, data, dan Keychain beda): **Luma** untuk dipakai sehari-hari (`make release`, hanya dari `master`) dan **Luma Dev** untuk nyoba fitur yang belum di-merge (`make dev`).

### Tes ke OpenRouter beneran (opsional)

Taruh `OPENROUTER_API_KEY=sk-or-...` di `.env` di root repo (sudah di-gitignore), lalu:

```bash
make live              # model default
make live m=<model id> # model lain
```

Tanpa key, tes ini di-skip.

## Status

MVP lagi dikerjakan dan dipakai sendiri buat baca. Rencana berikutnya (Recap bacaan, import Markdown/PDF, dsb.) ada di [docs/ideas/](docs/ideas/) dan belum dikerjakan.
