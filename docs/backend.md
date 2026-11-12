# Backend (Cloudflare)

> Status: rencana, belum ada kode. Keputusan dari diskusi 9 November 2026. Induk: [#197](https://github.com/choiruladamm/luma/issues/197).

App tetap **local-first**: Drift di device sumber kebenaran, semua fitur baca/AI/cari jalan tanpa backend. Backend cuma nambah akun, kuota AI subsidi, backup cloud, dan sync antar device.

## Stack

| Layer | Pilihan | Catatan |
|---|---|---|
| API | Cloudflare Workers + Hono | Folder `apps/backend`, route di bawah `/v1` |
| Database | D1 (SQLite) + Drizzle | Migrasi lewat `drizzle-kit generate` → `wrangler d1 migrations apply` |
| File | R2 | Semua key per user: `u/{userId}/...` |
| Auth | Better Auth + plugin `bearer` | Butuh flag `nodejs_compat` |
| Tooling | Bun + Wrangler | Bun cuma tooling, runtime tetap Workers |
| Test | `vitest` + `@cloudflare/vitest-pool-workers` | `make backend-test` |

Tidak dipakai: Workers Static Assets untuk frontend (app-nya mobile; cuma halaman statis `/privacy` dan hapus akun), AI Gateway (AI tidak lewat backend, lihat [AI](#ai-subsidi--byok)).

## Aturan free tier (wajib)

**Semua kode backend dan client yang memanggil backend wajib muat di free tier Cloudflare.** Tiap fitur baru atau perubahan pemanggilan backend harus memperbarui [anggaran request](#anggaran-per-aksi) di bawah. Fitur yang gak muat anggaran: desain ulang dulu, bukan naik ke plan berbayar.

### Batas

| Layanan | Batas free | Kalau lewat |
|---|---|---|
| Workers | 100rb request/hari, **CPU 10ms/request**, 50 subrequest/request, body 100MB | Request gagal (error 1027 / CPU exceeded), bukan tagihan |
| D1 | 5GB, ±5jt baris dibaca + 100rb baris ditulis per hari (index ikut dihitung) | Query gagal sampai reset 00.00 UTC |
| R2 | 10GB-bulan, 1jt operasi Class A (tulis/list) + 10jt Class B (baca) per bulan | **Ditagih** (R2 butuh metode bayar), jadi paling ketat dijaga |

Menunggu `fetch`/I/O tidak dihitung CPU; `crypto.subtle`, `JSON.parse`, dan kompresi dihitung. Angka dicek ulang di dashboard sebelum implementasi.

### Aturan client

- **Tanpa polling.** Gak ada timer yang manggil backend berkala. Pemicu hanya: app dibuka/resume, aksi user, atau perubahan lokal.
- **Jarak minimum per pemicu otomatis**: sync paling cepat 5 menit sekali saat resume; push setelah perubahan lokal di-debounce 60 detik; backup otomatis 24 jam.
- **Dedupe sebelum kirim**: `sync_outbox` ber-PK `(kind, key)`, jadi 100 update posisi baca = 1 record.
- **Batch**: push maks 500 record per request; satu request `POST /v1/files/missing` untuk semua nama file.
- **Retry**: hanya untuk error jaringan/5xx, backoff eksponensial (maks 3 kali per pemicu). 4xx tidak di-retry. Hormati `Retry-After` pada 429/503. Pemicu otomatis yang gagal menunggu pemicu berikutnya, bukan loop.
- **Cache respons yang jarang berubah**: `/v1/ai/config` 24 jam, `/v1/ai/usage` cuma saat Pengaturan dibuka (cache 1 jam), key AI disimpan sampai 401.
- **Sesi tidak dicek tiap app dibuka**: token dipakai langsung; 401 baru memicu login ulang.

### Aturan server

- **CPU**: upload/download di-stream (`c.req.raw.body` → R2), tidak di-buffer atau di-hash di Worker. Tidak ada scrypt JS. PBKDF2 (dev saja) pakai iterasi yang muat 10ms, diukur di `wrangler dev`. Payload push divalidasi ringan; batas ukuran body (sync 1MB) ditolak sebelum `JSON.parse`.
- **D1**: satu request = satu `db.batch()`; upsert yang datanya sama tidak menulis ulang (`ON CONFLICT ... WHERE excluded.updated_at > updated_at`). Index seminimal mungkin (tiap index = baris tulis tambahan).
- **Subrequest ≤ 50**: hapus R2 pakai `delete([...keys])` per 1000 key; kerja yang lebih besar (mis. hapus akun dengan banyak file) dicicil lewat beberapa request dari client atau Cron Trigger, bukan satu request raksasa.
- **R2 dibatasi per user**: kuota penyimpanan per user (awal 1GB, `vars` `USER_STORAGE_BYTES`) dicek di `PUT /v1/files/:name` dari tabel `user_storage(user_id, bytes)`; lewat → 413. File maks 100MB. Retensi backup 10 snapshot.
- **Rate limit**: binding Workers Rate Limiting per user (dan per IP untuk auth/key AI). Lewat → 429 + `Retry-After`.
- **Saklar darurat**: `vars` `SYNC_ENABLED`, `BACKUP_ENABLED`, `AI_KEY_ENABLED`. `false` → endpoint balas 503 + `Retry-After: 3600` tanpa menyentuh D1/R2; client berhenti sampai pemicu berikutnya setelah jeda itu.

### Anggaran per aksi

Perkiraan untuk satu user aktif per hari. Wajib diperbarui saat implementasi berubah.

| Aksi | Request Worker | Baris D1 | Operasi R2 |
|---|---|---|---|
| Login | 1–2 (jarang) | ±3 tulis | - |
| Auth per request (cek sesi bearer) | termasuk di request lain | 1 baca | - |
| Key AI (`POST /v1/ai/key`) | 0 (sudah ada key), 1 saat pertama / 401 | 1 baca / 1 tulis | - |
| Usage/config AI | ≤ 2 (Pengaturan dibuka) | 1 baca | - |
| Backup otomatis | 2 + jumlah file baru (1×/hari) | - | 1 list + 1–2 tulis + hapus snapshot lama |
| Sync (resume + debounce) | ±10–30 | ±50–300 tulis, ±100–500 baca | - |
| Download buku di device baru | 1 per buku (sekali) | - | 1 baca per buku |

Patokan kapasitas: **±50 request/user/hari → ±2.000 user aktif/hari** di batas Workers; batas pertama yang kena realistisnya **D1 100rb baris tulis/hari** (±300–2.000 user tergantung aktivitas sync). Sync pertama (upload semua `ai_results` lama) dicicil maks 10 batch per pemicu supaya satu user tidak menghabiskan kuota tulis harian.

### Pemantauan

Workers Logs + dashboard Analytics (request, CPU p99, error) dicek tiap rilis backend. Tanda bahaya: CPU p99 > 5ms, error 1027, atau request/hari > 50rb (separuh batas) → cari pemicu yang bocor sebelum menambah fitur.

## Lingkungan

`wrangler` env `dev` dan `prod`, masing-masing D1, R2, dan workspace OpenRouter sendiri. Luma Dev (`id.ruma.luma.dev`) → env `dev`, Luma (`id.ruma.luma`) → `prod`, sama seperti aturan flavor di `CLAUDE.md`. `baseUrl` di Flutter ditentukan per flavor.

Log: `observability.enabled: true` (Workers Logs). Pemulihan D1: Time Travel bawaan. Deploy manual `make backend-deploy`; CI/CD ditunda.

## Auth

Better Auth dipasang di Hono (`app.all("/v1/auth/*", ...)`), instance dibuat per request karena binding D1 baru ada di dalam request.

- **Dev**: email + password, hanya kalau `ENV != prod`. Hash password diganti PBKDF2 lewat `crypto.subtle` (`emailAndPassword.password.hash/verify`); scrypt default terlalu berat untuk CPU 10ms.
- **Prod**: Google lewat **idToken native** (`google_sign_in`, `serverClientId` = web client ID). Server: `socialProviders.google.clientId` berupa array web/iOS/Android. Tanpa redirect OAuth di mobile.
- **Sign in with Apple**: wajib (App Store 4.8) kalau masuk App Store sambil nawarin Google; polanya sama (idToken). Ditunda sampai rilis App Store.
- **Gerbang beta**: kode undangan (`databaseHooks.user.create.before`). Dicabut saat pricing siap.
- **Flutter**: tanpa SDK resmi; panggil REST langsung lewat `dio` (`/sign-in/email`, `/sign-up/email`, `/sign-in/social` dengan `{provider: "google", idToken: {token}}`). Token dari header `set-auth-token` disimpan di `flutter_secure_storage`, dikirim sebagai `Authorization: Bearer`.

### Sesi & akun

- **Sesi kedaluwarsa / 401**: sync, backup cloud, dan pengambilan key AI berhenti diam-diam, muncul banner "Login lagi". Baca, cache, dan BYOK tetap jalan.
- **Logout**: data lokal tetap.
- **Ganti akun**: login dengan akun yang beda dari akun terakhir di device → konfirmasi "Data di HP ini bakal dihapus dulu", supaya sync tidak mencampur data dua orang.
- **Hapus akun** (wajib App Store 5.1.1(v) dan Play Store): `DELETE /v1/me` menghapus baris D1 user, semua objek R2 `u/{userId}/`, dan key OpenRouter-nya. Play Store butuh URL web untuk hapus akun → halaman kecil di Worker.
- **Kebijakan privasi**: halaman statis `/privacy`: data yang disimpan (akun, backup, data sync), teks yang dikirim ke OpenRouter, cara hapus akun.

## AI (subsidi + BYOK)

AI tetap dipanggil **langsung dari device ke OpenRouter**; `OpenRouterService`, streaming, `ai_calls`, dan retry tidak berubah. Yang berubah cuma asal key:

```
key = ai.byokKey ?? ai.lumaKey
```

- **Subsidi (default setelah login)**: backend membuat key OpenRouter per user lewat management key (`POST /api/v1/keys`), dibuat **lazy** saat AI pertama kali dipakai, bukan saat daftar.
- **BYOK**: user isi key OpenRouter sendiri (field paste yang sudah ada). Kalau diisi, menang; dikosongkan → balik ke subsidi. Belum login → BYOK seperti sekarang.
- API key (subsidi maupun BYOK) tetap hanya di secure storage, tidak ikut backup/sync.

### Endpoint

| Endpoint | Fungsi |
|---|---|
| `POST /v1/ai/key` | Belum punya → buat key; sudah → kirim key yang sama (satu key per user, dua device tidak dapat kuota ganda). Ditolak kalau `banned` |
| `GET /v1/ai/usage` | Usage + limit dari OpenRouter (`GET /keys/{hash}`) untuk "Sisa kuota" |
| `GET /v1/ai/config` | Daftar model yang diizinkan untuk mode subsidi |

D1: `ai_keys(user_id unique, key_hash, key_enc, limit, expires_at)`. Key disimpan terenkripsi AES-GCM (kunci di secret Worker) karena OpenRouter cuma memberi teks key sekali saat dibuat.

### Batas & pengaman

| Risiko | Pengaman |
|---|---|
| Biaya per user | `limit: 0.02`, `limit_reset: "daily"` → maks ±$0.60/bulan per user, ±30–50 tap/hari |
| Total biaya | Budget guardrail workspace OpenRouter **$5/bulan**. Habis → semua key subsidi 402 → "Kuota gratis lagi abis, pakai key sendiri dulu yuk". Saldo OpenRouter tanpa auto top-up sebagai lapis kedua |
| Key diekstrak dari device | Limit harian kecil + `expires_at` 30 hari. 401 → app panggil `POST /v1/ai/key` → key lama dihapus, key baru dibuat. `banned` → `DELETE /keys/{hash}` |
| Model mahal | Workspace `luma-subsidi` dengan default guardrail `allowed_models` (model default + kandidat murah + **model embedding** Ngobrolin). Mode subsidi: pemilih model hanya menampilkan daftar dari `/v1/ai/config` |
| Spam akun | Login prod hanya Google, key lazy, `user_id` unique, rate limit `POST /v1/ai/key` per IP + per user (binding Workers Rate Limiting), kode undangan selama beta |

Batas terburuk: **biaya subsidi per bulan ≤ min(budget workspace, jumlah user × limit bulanan per user)**, ditegakkan OpenRouter.

Angka di `vars` `wrangler.jsonc` (`AI_DAILY_LIMIT_USD`, `AI_MONTHLY_BUDGET_USD`). Ubah limit → key yang sudah ada di-`PATCH`. Paket berbayar nanti = limit per key lebih besar.

Dicek saat implementasi: `POST /keys` menerima `workspace_id`; budget USD bulanan di guardrail bisa diatur lewat API. Kalau tidak: assign guardrail per key (`POST /guardrails/{id}/assignments/keys`) + saldo terbatas + cron yang mencabut key subsidi saat total bulan ini lewat budget.

## Backup cloud

Memakai alur [backup.md](backup.md) yang sudah ada; yang diganti cuma tujuan (share sheet → R2). Backup lewat share sheet tetap ada.

Zip penuh tidak di-upload (bisa ratusan MB, lewat batas body 100MB). Isinya dipisah:

| Isi | Key R2 | Kapan |
|---|---|---|
| File buku & cover | `u/{userId}/files/{fileName}` (nama file sudah berbasis hash) | Sekali, hanya yang belum ada |
| Snapshot DB | `u/{userId}/backups/{ts}.zip` (`manifest.json` + `luma.sqlite`) | Tiap backup |

| Endpoint | Fungsi |
|---|---|
| `POST /v1/files/missing` | `{names}` → `{missing}` |
| `PUT /v1/files/:name` | Body di-stream ke R2, maks 100MB |
| `PUT /v1/backups` | Zip kecil, `customMetadata` dari manifest; hapus snapshot lama di luar 10 terakhir |
| `GET /v1/backups` | List lewat `R2.list({prefix, include: ["customMetadata"]})`, tanpa tabel D1 |
| `GET /v1/backups/:ts` | Download |

- **Pemicu**: otomatis saat app dibuka/resume kalau login dan backup cloud terakhir > 24 jam (diam-diam, gagal = coba lagi resume berikutnya) + tombol "Backup ke cloud" di Pengaturan (sheet progres + toast yang sama). Sukses mengisi `lastBackupAt`, jadi banner pengingat ikut tenang.
- **Retensi**: 10 snapshot terakhir, dihapus di request `PUT` yang sama (bukan lifecycle rule umur, supaya jeda lama tidak menghapus semuanya).
- **Restore**: download zip DB → download file yang belum ada lokal → folder ekstrak sementara → validasi & swap `RestoreService` yang sudah ada (refactor kecil: terima folder hasil ekstrak).

## Sync antar device ([#109](https://github.com/choiruladamm/luma/issues/109))

Per baris, last-write-wins dengan aturan merge per tabel, memakai **kunci alami** (tanpa kolom `uid`). Kunci diturunkan dari isi, jadi dua device yang sudah punya buku yang sama otomatis menyatu, bukan dobel.

### Kunci global

| Data | Kunci |
|---|---|
| Buku | `hash` (EPUB/PDF) atau `md:{bookKey}` (Markdown) |
| Bab | `{bookKey}/{sortOrder}`, hanya berlaku kalau `parserVersion` sama |
| `ai_results`, `ai_breakdowns` | `{babKey}/{groupIndex}` |
| `reading_progress` | `{bookKey}` |
| `reading_sessions` | `{bookKey}/{startedAt ms}` |
| `settings` | `key`, hanya allowlist |
| `chat_sessions` | `{bookKey}/{createdAt ms}` |
| `chat_turns` | `{sessionKey}/{sequence}`, hanya turn yang sudah selesai |

### Aturan merge

| Tabel | Aturan |
|---|---|
| `books` (metadata, judul edit, cover default) | Terbaru menang; `firstOpenedAt`/`finishedAt` ambil paling awal; `readingSeconds` ambil terbesar |
| `reading_progress` | Terbaru menang |
| `reading_sessions` | Append-only, tidak konflik |
| `ai_results`, `ai_breakdowns` | `promptVersion` lebih tinggi menang, lalu `createdAt` terbaru |
| `settings` | Terbaru menang per key; `backup.*`, `catalog.*`, `lastBackupAt` tidak ikut (per device). `ai.model` ikut |
| `chat_sessions`, `chat_turns` | Terbaru menang; turn `running` tidak di-push |
| Hapus buku | Tombstone; device lain ikut hapus, cascade lokal membereskan sisanya |

Tidak ikut: `chapters`/`paragraphs` (diparse ulang dari file), `catalog_books`, `chat_indexes`, `chat_vectors` (turunan). Ditunda: `ai_calls`, `chat_chapter_notes`.

### Mekanisme

Server (D1):

```sql
records(user_id, kind, key, data JSON, updated_at, deleted, seq,
        PRIMARY KEY (user_id, kind, key))
```

- `POST /v1/sync/push {schemaVersion, records}` → merge, isi `seq` baru. Batch maks 500.
- `GET /v1/sync/pull?since={seq}` → baris dengan `seq` lebih besar. Cursor dari server, bukan jam device.

Client (butuh migrasi Drift: tabel baru + trigger, tanpa ubah kolom tabel lama):

- `sync_outbox(kind, key, updatedAt)` diisi **trigger SQLite** di tiap tabel yang di-sync; repository tidak disentuh.
- Push: outbox → ubah ID lokal ke kunci alami → kirim.
- Pull: kunci alami → ID lokal → terapkan, trigger dimatikan selama pull supaya tidak di-push balik.
- `sync_inbox`: record yang belum bisa diterapkan (buku belum ter-download, `parserVersion` beda, atau `schemaVersion` record lebih baru dari app) → dicoba lagi setelah import / update app.

### File buku

- Folder `u/{userId}/files/` yang sama dengan backup cloud.
- Device baru: semua buku di-download + import otomatis di background, setting "Sync cuma lewat Wi-Fi" (default nyala), indikator "Nyinkronin 3/12 buku" di Rak.
- **Buku Markdown** (tanpa file sumber): chapters + paragraphs (dengan `groupIndex`) di-dump ke `md-{bookKey}-{contentRevision}.json.gz`, diperlakukan sebagai file. Bab ditambah di dua device sekaligus → terakhir menang.

### Versi app

Route di bawah `/v1`. Push membawa `schemaVersion`; pull menahan record dengan versi lebih baru di `sync_inbox` sampai app di-update (build sideload lama tetap jalan).

### Ditolak

PowerSync / ElectricSQL / Turso (di luar Cloudflare, mengganti fondasi Drift), CRDT (berlebihan untuk satu user beberapa device), sync = restore snapshot terbaru (perubahan device lain hilang).

## Urutan kerja

1. Scaffold `apps/backend` ([#198](https://github.com/choiruladamm/luma/issues/198), Hono, Drizzle, D1, R2, env dev/prod, observability, vitest, target Makefile)
2. Auth ([#199](https://github.com/choiruladamm/luma/issues/199), email dev, Google prod, kode undangan, sesi di Flutter, hapus akun, `/privacy`)
3. Key AI ([#200](https://github.com/choiruladamm/luma/issues/200), subsidi + BYOK, guardrail, budget)
4. Backup cloud ([#201](https://github.com/choiruladamm/luma/issues/201))
5. Sync ([#109](https://github.com/choiruladamm/luma/issues/109), migrasi outbox/inbox, push/pull, file buku, ganti akun, versi app)

## Ditunda

| Item | Dibuka kalau |
|---|---|
| OpenRouter OAuth PKCE (tombol "Hubungkan OpenRouter") ([#202](https://github.com/choiruladamm/luma/issues/202)) | Pengguna BYOK selain pemilik app. `callback_url` hanya `https`/localhost → route Worker redirect ke `luma://` / `luma-dev://`; cek dulu apakah tukar kode butuh management key |
| Proxy LLM ([#106](https://github.com/choiruladamm/luma/issues/106)) | Butuh kontrol di level prompt atau model yang tidak boleh diakses dari client |
| Pricing / pembayaran ([#203](https://github.com/choiruladamm/luma/issues/203)) | Kuota gratis terbukti kurang; paket = limit per key |
| App Attest / Play Integrity ([#204](https://github.com/choiruladamm/luma/issues/204)) | Spam lolos semua lapisan di atas |
| Cron deteksi abuse ([#205](https://github.com/choiruladamm/luma/issues/205)) | Tagihan subsidi aneh |
| GC file R2 yatim ([#206](https://github.com/choiruladamm/luma/issues/206)) | R2 mendekati 10GB |
| Enkripsi E2E backup/sync ([#207](https://github.com/choiruladamm/luma/issues/207)) | App dipakai orang lain dan isi chat/terjemahan perlu dilindungi dari pemilik akun Cloudflare |
| Frontend web ([#208](https://github.com/choiruladamm/luma/issues/208)) | Mau reader versi web |
| CI/CD deploy ([#209](https://github.com/choiruladamm/luma/issues/209)) | Deploy manual mulai merepotkan |
