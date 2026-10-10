<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="apps/mobile/assets/brand/logo-lockup-dark.svg">
    <img src="apps/mobile/assets/brand/logo-lockup.svg" alt="Luma" height="84">
  </picture>
</p>

<p align="center">
  Reader EPUB dan Markdown untuk iOS dan Android. Tap satu paragraf, langsung muncul terjemahan Indonesia dan maknanya, tanpa keluar dari halaman baca.
</p>

<div align="center">
  <img src="docs/images/showcase-4.png" alt="Layar Luma: rak, baca, terjemahan, Bedahin, dan Pengaturan" width="100%">

<details>
<summary>Intip showcase lainnya</summary>
<br>
  <img src="docs/images/showcase-1.png" alt="Rak, baca, terjemahan, dan Bedahin" width="100%">
  <br><br>
  <img src="docs/images/showcase-2.png" alt="Alur: tap paragraf, terjemahan, bedah" width="100%">
  <br><br>
  <img src="docs/images/showcase-3.png" alt="Daftar isi, font, dan Pengaturan" width="100%">
</details>
</div>

## Features

- **Tap paragraf → terjemahan + makna**, ditulis bertahap (streaming) di bottom sheet.
- **Bedahin**: bedah gagasan jadi beberapa bagian, dengan sambungan ke bagian lain di buku.
- **Cache hasil AI**: grup yang pernah di-tap gak manggil LLM lagi.
- **Import EPUB dan Markdown** lewat parser sendiri, jalan di isolate.
- **Rak buku** dengan cover, progres, dan posisi baca per buku.
- **Halaman baca imersif** dengan pengaturan font, ukuran, jarak baris, dan tema terang/gelap.
- **Backup & restore** semua data ke satu file `.zip`.

Data tersimpan lokal (SQLite lewat Drift). Yang keluar dari device hanya teks grup yang di-tap, dikirim ke OpenRouter pakai API key sendiri.

## Tech stack

Flutter ([FVM](https://fvm.app)) · Riverpod 3 · Drift · go_router · freezed · [OpenRouter](https://openrouter.ai) (model bisa diganti di Pengaturan) · `flutter_secure_storage` untuk API key (tidak ikut backup).

## Getting started

Butuh Flutter lewat FVM, plus Xcode (iOS) dan/atau Android SDK.

```bash
make get      # pub get
make gen      # codegen (drift, freezed)
make check    # format, analyze, test
make run      # debug di device / simulator
make help     # semua perintah
```

Isi API key OpenRouter (`sk-or-...`) di **Pengaturan** untuk memakai fitur AI.

Build ke device: `make dev` / `make dev-android` (Luma Dev, branch apa saja), `make release` / `make release-android` / `make apk` (Luma, hanya dari `master`).

Keystore Android (sekali, simpan di luar repo):

```bash
keytool -genkeypair -v -keystore ~/.android/luma-release.jks -alias luma \
  -keyalg RSA -keysize 2048 -validity 10000
```

Lalu buat `apps/mobile/android/key.properties` (gitignored): `storeFile`, `storePassword`, `keyAlias=luma`, `keyPassword`.
