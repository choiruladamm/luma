# Backup & Restore

## Kenapa masuk MVP

Luma diinstall tanpa Apple Developer Program berbayar, jadi build harus diinstall ulang dari Xcode **setiap 7 hari**.

- Install ulang **di atas app yang sudah ada** (bundle ID & tim signing sama) biasanya **mempertahankan data**.
- Data **hilang** kalau app dihapus (mis. saat membereskan masalah signing), bundle ID berubah, atau ganti HP.

Terjemahan di `ai_results` (dan bedahan di `ai_breakdowns`) dibayar pakai saldo OpenRouter dan progres baca tidak bisa dibuat ulang, jadi wajib ada backup manual yang gampang.

## Prinsip

- **Satu file berisi semuanya**, disimpan **di luar app** (Files / iCloud Drive / AirDrop ke Mac). Backup yang disimpan di dalam folder app ikut hilang kalau app dihapus.
- **Restore = ganti semua data** (bukan merge). Merge ditunda.
- **Aman**: restore diekstrak ke folder sementara dulu, data lama baru diganti kalau semua langkah berhasil.
- **API key tidak ikut** di-backup (alasan keamanan). Setelah restore, kalau API key kosong, app minta diisi ulang.

## Isi file backup

Nama: `luma-backup-YYYYMMDD-HHmm.zip` (pakai ekstensi `.zip` biasa supaya tidak perlu daftar tipe file custom di iOS).

```
luma-backup-20261006-2130.zip
├── manifest.json
├── luma.sqlite        ← snapshot database Drift
├── books/             ← file EPUB asli ({hash}.epub)
└── covers/            ← gambar cover ({hash}.png)
```

`manifest.json`:

```json
{
  "format": "luma-backup",
  "formatVersion": 1,
  "appVersion": "0.1.0",
  "schemaVersion": 1,
  "createdAt": "2026-10-06T21:30:00+07:00",
  "counts": { "books": 7, "aiResults": 1240 }
}
```

## Alur export (backup)

1. Pengaturan → "Backup sekarang"
2. Buat snapshot database yang konsisten dengan `VACUUM INTO '<tmp>/luma.sqlite'` (aman walau database sedang dipakai / mode WAL)
3. Tulis `manifest.json`
4. Zip snapshot + folder `books/` + `covers/` (pakai package `archive`, jalankan di isolate karena file EPUB bisa besar)
5. Buka share sheet (`share_plus`) → user pilih "Save to Files", iCloud Drive, atau AirDrop
6. Simpan `lastBackupAt` di tabel `settings`, hapus file zip sementara

**Implementasi** (`BackupService` + `BackupController`):

- Snapshot `VACUUM INTO` ke folder sementara (`Directory.systemTemp`), hitung jumlah buku & `ai_results` buat manifest. `appVersion` dari konstanta yang dicek sama `version` di pubspec (test).
- Zip di isolate (`Isolate.spawn` + port progres), urutan: `books/`, `covers/` (disimpen tanpa kompresi, udah kekompres), `luma.sqlite`, `manifest.json` (dikompres). Sheet "Lagi ngebungkus backup..." (board 26) nampilin nama file, persen, dan centang per tahap: buku → terjemahan (DB) → pengaturan (manifest). "Batalin" matiin isolate-nya, folder sementara dibuang.
- Sheet progres ditutup dulu, baru menu share iOS muncul. Backup terakhir cuma dicatet kalau share-nya **beneran disimpen/dikirim** (`ShareResultStatus.success`); ditutup tanpa milih = gak dicatet. Zip sementara selalu dihapus.
- Berhasil → toast "Backup kelar, aman!" + "12,4 MB · nama file" (board 27). Gagal → toast "Yah, backup gagal".
- Pengaturan, bagian "Backup & pulihin": kapan backup terakhir ("Barusan" kalau < 1 jam, "Kemarin", "3 hari lalu", ...), nama + ukuran file, atau "Belum pernah backup" (ikon pink). Tombol "Pulihin dari backup" nyusul di #25.
- Board nulis nama file `luma-backup-2026-10-06.luma`; yang dipake tetep `luma-backup-YYYYMMDD-HHmm.zip` (zip biasa, gak perlu daftar tipe file custom di iOS).

## Alur import (restore)

1. Pengaturan → "Pulihin dari backup" → pilih file `.zip` via `file_picker`
2. Ekstrak ke folder sementara
3. Validasi:
   - `manifest.json` ada dan `format` = `luma-backup`
   - `schemaVersion` backup **≤** schema app sekarang (backup dari versi lebih baru → tolak)
   - `luma.sqlite` bisa dibuka
4. Tampilkan ringkasan: jumlah buku, jumlah terjemahan, tanggal backup
5. Konfirmasi: "Semua data di Luma sekarang bakal diganti. Lanjut?"
6. Tutup koneksi Drift → ganti file database + folder `books/` & `covers/` → buka lagi database (migrasi Drift otomatis jalan kalau backup dari schema lama). Backup dari sebelum schema 4: terjemahannya jadi `promptVersion` 1, diterjemahin ulang pas grupnya dibuka
7. Invalidate provider Riverpod (atau restart ke Rak)
8. Gagal di langkah mana pun → hapus folder sementara, data lama tetap utuh

**Implementasi** (`RestoreService`, alurnya di Pengaturan):

- Pilih `.zip` (path lokal, dibaca streaming). Ekstrak di isolate ke `Directory.systemTemp`, **cuma file yang dikenal**: `manifest.json`, `luma.sqlite`, `books/<nama>`, `covers/<nama>`; path aneh (`../`, absolut, subfolder) dilewatin.
- Cek: bukan zip / manifest gak ada / `format` salah → "Ini bukan backup Luma"; `schemaVersion` > app → "Backup-nya dari Luma yang lebih baru" (nyebut dua versinya); `luma.sqlite` gak bisa dibuka → "File backup-nya rusak". Salinan sementara dibuka beneran (migrasi jalan di salinan), jadi database rusak ketauan sebelum apa pun diganti. Semua sheet gagal punya "Pilih file lain".
- Ringkasan (board 28): nama file, kapan & pake Luma versi berapa, jumlah buku & terjemahan, WarningBox (nyebut jumlah buku sekarang), ConfirmCheck; "Ganti & pulihin" baru aktif kalau dicentang. "Batal" = folder sementara dibuang.
- Ganti: tutup Drift → `books/`, `covers/`, `luma.sqlite(-wal/-shm)` dipindah ke `*.old` → isi backup dipindah masuk → `*.old` dihapus. Gagal di tengah → semua yang udah dipindah dibalikin urutan kebalik (ada test-nya). Abis itu `appDatabaseProvider` di-invalidate (database lama/baru dibuka lagi, provider data ikut dibangun ulang).
- Berhasil → balik ke Rak + toast "Sip, data lo udah balik!" · "N buku · N terjemahan"; kalau API key kosong, toast-nya punya baris kedua "API key gak ikut backup, isi ulang dulu biar bisa nerjemahin." + "Isi key" (6 detik). Gagal ganti → "Yah, gagal mulihin", data lama utuh.
- Teks board "File backup Luma itu yang akhirannya .luma" disesuaiin jadi nama `luma-backup-…zip`. Tile ringkasan dilabelin "terjemahan" (manifest ngitung baris `ai_results` = grup, bukan paragraf).

## Pengingat backup

- Pengaturan menampilkan "Backup terakhir: 3 hari lalu" (atau "Belum pernah backup").
- Kalau `lastBackupAt` lebih dari **6 hari** (sebelum siklus install ulang 7 hari), tampilkan banner kecil di Rak: "Udah 6 hari belum backup nih" dengan tombol "Backup".
- Banner bisa ditutup, muncul lagi besoknya.
- **Implementasi:** hitungan per tanggal kalender dari backup terakhir; kalau belum pernah backup, dari buku pertama yang diimport (rak kosong = gak ada banner). Muncul mulai hari ke-6. Ditutup → tanggalnya disimpen di `settings` (`backup.reminderDismissedAt`), nongol lagi besok. Banner pink (board 24) ada di paling atas area scroll Rak; teksnya: hari ke-6 "Udah 6 hari belum backup nih" · "Besok jatah install ulang. Amanin data lo dulu yuk.", lebih dari itu "Udah N hari belum backup nih" · "Amanin data lo dulu yuk, sebelum keburu install ulang.", belum pernah "Belum pernah backup nih" · "Data lo cuma ada di HP ini doang. Amanin dulu yuk.". "Backup sekarang" langsung jalanin backup di Rak (sheet progres & toast-nya sama kayak di Pengaturan).

## Catatan

- Jangan bandingkan absolute path dari backup. Semua path di database sudah berupa nama file ([data-model.md](data-model.md)), jadi tetap valid setelah restore.
- Ukuran backup kira-kira = total ukuran EPUB + sedikit untuk database. Tampilkan ukuran setelah backup selesai.
- Unit test: round-trip export → restore ke database kosong menghasilkan data yang sama.

## Ditunda (setelah MVP)

- Export/import **per buku** (satu buku + terjemahannya, untuk dipindah atau dibagikan)
- Restore **merge** (gabung dengan data yang ada)
- Export terjemahan + makna ke Markdown (nyambung dengan Recap)
