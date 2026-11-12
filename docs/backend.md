# Backend (Cloudflare)

> Status: rencana, belum ada kode. Keputusan dari diskusi 9 November 2026. Induk: [#197](https://github.com/choiruladamm/luma/issues/197).

App tetap **local-first**: Drift di device sumber kebenaran, semua fitur baca/AI/cari jalan tanpa backend. Backend cuma nambah akun, kuota AI subsidi, backup cloud, dan sync antar device.

## Gambaran sistem

Device tetap sumber kebenaran. Worker cuma melayani akun, key AI, backup, dan sync; AI dipanggil langsung dari device ke OpenRouter.

```mermaid
flowchart LR
  subgraph Device["Device iOS / Android"]
    direction TB
    App["Luma Flutter<br/>UI → ViewModel → Repository"]
    Drift[("Drift SQLite<br/>sumber kebenaran")]
    KC[["Secure storage<br/>token · ai.lumaKey · ai.byokKey"]]
    App --> Drift
    App --> KC
  end
  subgraph CF["Cloudflare free tier"]
    direction TB
    W["Worker Hono /v1"]
    D1[("D1<br/>akun · ai_keys<br/>user_storage · records")]
    R2[("R2<br/>u/userId/files<br/>u/userId/backups")]
    RL["Rate Limiting"]
    W --> D1
    W --> R2
    W --> RL
  end
  subgraph EXT["Layanan luar"]
    direction TB
    G["Google Sign-In"]
    OR["OpenRouter<br/>model AI"]
  end
  App -- "Bearer: auth · key AI · backup · sync" --> W
  W -. "verifikasi idToken" .-> G
  W -- "management key" --> OR
  App == "AI langsung: key subsidi / BYOK" ==> OR
  App -. "google_sign_in" .-> G
```

## Stack

| Layer | Pilihan | Catatan |
|---|---|---|
| API | Cloudflare Workers + Hono | Folder `apps/backend`, route di bawah `/v1` |
| Database | D1 (SQLite) + Drizzle | Migrasi lewat `drizzle-kit generate` → `wrangler d1 migrations apply` |
| File | R2 | Semua key per user: `u/{userId}/...` |
| Auth | Better Auth + plugin `bearer` | Butuh flag `nodejs_compat` |
| Tooling | Bun + Wrangler | Bun cuma tooling, runtime tetap Workers |
| Test | Vitest + `@cloudflare/vitest-plugin` (`cloudflareTest()`), MSW lewat `@msw/cloudflare` | `make backend-test`, lihat [Strategi test](#strategi-test) |

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
| Login / daftar (#199) | 1–2, sekali per device | ±3–6 tulis | - |
| Auth per request (cek sesi bearer, #199) | termasuk di request lain | 1 baca (+1 tulis maks sekali sehari) | - |
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

Better Auth 1.7 dipasang di Hono (`/v1/auth/*`) dengan adapter `@better-auth/drizzle-adapter` (`provider: "sqlite"`, `usePlural: true`). Schema: `bunx auth@latest generate --config scripts/auth-schema.config.ts --output src/db/auth-schema.ts` (kolom langsung `snake_case`) → `bunx drizzle-kit generate` → `make backend-migrate e=dev`.

**CPU** (diukur `wrangler tail` di env dev, 12 November 2026):

| Endpoint | Median | Catatan |
|---|---|---|
| `GET /v1/me` (cek sesi) | 2 ms | Jalur panas. Gak lewat Better Auth: `findSessionUser` satu query join `sessions` + `users` |
| `POST /v1/auth/sign-in/email` | 19 ms | Better Auth + PBKDF2. Sekali per device, masuk toleransi "sesekali lewat" Cloudflare |
| `POST /v1/auth/sign-up/email` | ±50 ms | Sekali per akun |

- Instance Better Auth mahal dibuat, jadi dipakai ulang per isolate (`getAuth`, kunci objek `env`).
- **Aturan**: route Luma (`/v1/me`, sync, backup, key AI) cek sesi lewat `requireSession` (D1 langsung), **jangan** `auth.api.getSession`. Better Auth cuma untuk `/v1/auth/*`.
- Cloudflare memberi tiap isolate toleransi untuk request yang *sesekali* lewat 10 ms; yang *konsisten* lewat dihentikan (error 1102). Login boleh sesekali lewat, jalur panas tidak.

- **Dev**: email + password, hanya kalau `ENV != prod`. Hash password diganti PBKDF2-SHA256 lewat `crypto.subtle` (`emailAndPassword.password.hash/verify`), 20.000 iterasi (±1,5 ms di laptop), iterasi ikut disimpan di hash. Di bawah anjuran OWASP (600.000) karena batas CPU; diterima karena login email cuma ada di dev. Argon2id / scrypt / bcrypt (memory-hard, lebih tahan GPU) sudah dipertimbangkan: lewat JS/WASM puluhan–ratusan ms per hash, gak muat CPU 10 ms. **Aturan**: prod gak pernah menyimpan password; login selain Google = Sign in with Apple atau OTP email, bukan password.
- **Prod**: Google lewat **idToken native** (`google_sign_in`, `serverClientId` = web client ID). Server: `socialProviders.google.clientId` berupa array web/iOS/Android. Tanpa redirect OAuth di mobile.
- **Sign in with Apple**: wajib (App Store 4.8) kalau masuk App Store sambil nawarin Google; polanya sama (idToken). Ditunda sampai rilis App Store.
- **Gerbang beta**: kode undangan lewat header `x-invite-code` saat daftar, dipakai atomik di `databaseHooks.user.create.before` (satu `UPDATE … WHERE used_at IS NULL`), salah/terpakai → 403 `INVALID_INVITE_CODE`. Dimatikan lewat `vars` `INVITE_REQUIRED=false` saat pricing siap. Kode dibuat manual: `bunx wrangler d1 execute DB --env dev --remote --command "INSERT INTO invite_codes (code) VALUES ('BETA-XXXX')"`.
- **Google**: aktif kalau `vars` `GOOGLE_CLIENT_IDS` (web,ios,android, dipisah koma) diisi; secret `GOOGLE_CLIENT_SECRET`. Belum diisi (menunggu OAuth client ID).
- **Flutter**: tanpa SDK resmi; panggil REST langsung lewat `dio` (`/sign-in/email`, `/sign-up/email`, `/sign-in/social` dengan `{provider: "google", idToken: {token}}`). Token dari header `set-auth-token` (bentuk `<token>.<signature>`) disimpan di `flutter_secure_storage`, dikirim sebagai `Authorization: Bearer`. Error Better Auth `{code, message}` dibungkus server jadi format seragam `{error: {code, message}}`.

Alur login Google (prod):

```mermaid
sequenceDiagram
  autonumber
  actor U as User
  participant A as App Flutter
  participant G as Google SDK
  participant W as Worker /v1/auth
  participant D as D1
  U->>A: Tap "Masuk pakai Google"
  A->>G: google_sign_in (serverClientId = web)
  G-->>A: idToken
  A->>W: POST /v1/auth/sign-in/social {provider, idToken}
  W->>W: verifikasi idToken (aud = client ID web/iOS/Android)
  W->>D: user baru → cek kode undangan · upsert user + account · buat session
  W-->>A: 200 + header set-auth-token
  A->>A: simpan token di secure storage
  Note over A,W: request berikutnya pakai Authorization: Bearer token
  alt akun beda dari akun terakhir di device
    A->>U: konfirmasi "Data di HP ini bakal dihapus dulu"
  end
```

### Sesi & akun

**Login wajib** (keputusan 12 November 2026): app tanpa sesi tersimpan membuka layar Masuk dulu (redirect go_router), termasuk install yang sudah punya data. Supaya tetap local-first:

- **Sekali saja**: token sesi di secure storage. Ada token → app langsung terbuka tanpa menunggu backend, offline pun jalan. Gerbang cuma cek "ada token", bukan memanggil server.
- **Data lama**: data Drift yang sudah ada tidak disentuh; login pertama menjadikannya milik akun itu (ikut sync nanti).
- **Sesi kedaluwarsa / 401**: tidak mengunci app. Sync, backup cloud, dan pengambilan key AI berhenti diam-diam, muncul banner "Login lagi". Baca, cache, dan BYOK tetap jalan.
- **Logout**: data lokal tetap, kembali ke layar Masuk.
- **Risiko App Store 5.1.1**: Apple bisa menolak login wajib untuk app yang fitur intinya tidak berbasis akun. Diterima selama distribusi sideload; ditinjau ulang sebelum submit App Store.
- **Ganti akun**: login dengan akun yang beda dari akun terakhir di device → konfirmasi "Data di HP ini bakal dihapus dulu", supaya sync tidak mencampur data dua orang.
- **Hapus akun** (wajib App Store 5.1.1(v) dan Play Store): `DELETE /v1/me` menghapus baris D1 user, semua objek R2 `u/{userId}/`, dan key OpenRouter-nya. Play Store butuh URL web untuk hapus akun → halaman kecil di Worker.
- **Kebijakan privasi**: halaman statis `/privacy`: data yang disimpan (akun, backup, data sync), teks yang dikirim ke OpenRouter, cara hapus akun.

## AI (subsidi + BYOK)

AI tetap dipanggil **langsung dari device ke OpenRouter**; `OpenRouterService`, streaming, `ai_calls`, dan retry tidak berubah. Yang berubah cuma asal key:

```
key = ai.byokKey ?? ai.lumaKey
```

- **Subsidi (default)**: backend membuat key OpenRouter per user lewat management key (`POST /api/v1/keys`), dibuat **lazy** saat AI pertama kali dipakai, bukan saat daftar.
- **BYOK**: user isi key OpenRouter sendiri (field paste yang sudah ada). Kalau diisi, menang; dikosongkan → balik ke subsidi. Key BYOK yang sudah tersimpan sebelum login tetap dipakai setelah login.
- API key (subsidi maupun BYOK) tetap hanya di secure storage, tidak ikut backup/sync.

Alur key AI:

```mermaid
sequenceDiagram
  autonumber
  participant A as App
  participant W as Worker /v1/ai
  participant D as D1
  participant O as OpenRouter
  alt ai.byokKey diisi
    A->>O: chat/completions pakai key user
  else ai.lumaKey sudah ada
    A->>O: chat/completions pakai key subsidi
  else belum punya key subsidi
    A->>W: POST /v1/ai/key
    W->>D: cari ai_keys user
    opt belum ada / kedaluwarsa
      W->>O: POST /keys (limit 0.02 daily, expires 30 hari, workspace luma-subsidi)
      O-->>W: key + hash
      W->>D: simpan key_enc (AES-GCM)
    end
    W-->>A: key
    A->>A: simpan ai.lumaKey
    A->>O: chat/completions pakai key subsidi
  end
  O-->>A: stream jawaban
  opt 402 kuota subsidi habis
    A->>A: "Kuota gratis lagi abis, pakai key sendiri dulu yuk"
  end
  opt 401 key subsidi ditolak
    A->>W: POST /v1/ai/key (rotasi, sekali)
  end
```

### Endpoint

| Endpoint | Fungsi |
|---|---|
| `POST /v1/ai/key` | Belum punya → buat key; sudah → kirim key yang sama (satu key per user, dua device tidak dapat kuota ganda). Ditolak kalau `banned` |
| `GET /v1/ai/usage` | Usage + limit dari OpenRouter (`GET /keys/{hash}`) untuk "Sisa kuota" |
| `GET /v1/ai/config` | Daftar model yang diizinkan untuk mode subsidi |

D1: `ai_keys(user_id unique, key_hash, key_enc, limit_usd, expires_at)`. Key disimpan terenkripsi AES-GCM (kunci di secret Worker) karena OpenRouter cuma memberi teks key sekali saat dibuat.

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
| `POST /v1/files/missing` | `{names}` → `{missing}`, lewat satu `R2.list` prefix (bukan HEAD per file, batas 50 subrequest) |
| `PUT /v1/files/:name` | Body di-stream ke R2, maks 100MB |
| `PUT /v1/backups` | Zip kecil, `customMetadata` dari manifest; hapus snapshot lama di luar 10 terakhir |
| `GET /v1/backups` | List lewat `R2.list({prefix, include: ["customMetadata"]})`, tanpa tabel D1 |
| `GET /v1/backups/:ts` | Download |

Alur backup:

```mermaid
sequenceDiagram
  autonumber
  participant A as App
  participant W as Worker /v1
  participant D as D1
  participant R as R2
  Note over A: pemicu: buka/resume (login, > 24 jam) atau tombol manual
  A->>A: VACUUM INTO snapshot + manifest → zip kecil
  A->>W: POST /v1/files/missing {names}
  W->>R: list prefix u/userId/files/ (satu subrequest)
  W-->>A: {missing}
  loop tiap file yang belum ada
    A->>W: PUT /v1/files/:name (stream)
    W->>D: cek + tambah user_storage.bytes (lewat kuota → 413)
    W->>R: put u/userId/files/name
  end
  A->>W: PUT /v1/backups (zip DB)
  W->>R: put u/userId/backups/ts.zip + customMetadata
  W->>R: hapus snapshot di luar 10 terakhir
  W-->>A: 200
  A->>A: lastBackupAt = sekarang
```

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

Alur push/pull:

```mermaid
sequenceDiagram
  autonumber
  participant DB as Drift
  participant OB as sync_outbox
  participant S as Sync service
  participant W as Worker /v1/sync
  participant D as D1 records
  DB->>OB: trigger insert/update/delete (PK kind, key)
  Note over S: pemicu: resume (min 5 menit) / debounce 60 detik
  S->>OB: ambil maks 500
  S->>S: ID lokal → kunci alami
  S->>W: POST /v1/sync/push {schemaVersion, records}
  W->>D: db.batch: upsert sesuai aturan merge + seq++
  W-->>S: 200 {seq}
  S->>OB: hapus yang terkirim
  S->>W: GET /v1/sync/pull?since=seq
  W->>D: SELECT seq > since
  W-->>S: records
  S->>DB: trigger mati · kunci alami → ID lokal · terapkan
  alt buku belum ada / parserVersion beda / schemaVersion lebih baru
    S->>S: simpan di sync_inbox, coba lagi setelah import / update app
  end
```

### File buku

- Folder `u/{userId}/files/` yang sama dengan backup cloud.
- Device baru: semua buku di-download + import otomatis di background, setting "Sync cuma lewat Wi-Fi" (default nyala), indikator "Nyinkronin 3/12 buku" di Rak.
- **Buku Markdown** (tanpa file sumber): chapters + paragraphs (dengan `groupIndex`) di-dump ke `md-{bookKey}-{contentRevision}.json.gz`, diperlakukan sebagai file. Bab ditambah di dua device sekaligus → terakhir menang.

### Versi app

Route di bawah `/v1`. Push membawa `schemaVersion`; pull menahan record dengan versi lebih baru di `sync_inbox` sampai app di-update (build sideload lama tetap jalan).

### Ditolak

PowerSync / ElectricSQL / Turso (di luar Cloudflare, mengganti fondasi Drift), CRDT (berlebihan untuk satu user beberapa device), sync = restore snapshot terbaru (perubahan device lain hilang).

## Arsitektur kode

```
apps/backend/
├── wrangler.jsonc            # env dev/prod, D1, R2, rate limit, vars
├── drizzle.config.ts
├── migrations/               # hasil drizzle-kit; di-apply wrangler dan test
├── src/
│   ├── index.ts              # Hono app: middleware + mount route, export default
│   ├── env.ts                # tipe Bindings (hasil `wrangler types`)
│   ├── middleware/           # requestId, killSwitch, bodyLimit, session, rateLimit, onError
│   ├── db/schema.ts          # tabel Drizzle + schema Better Auth hasil generate
│   ├── lib/                  # crypto (AES-GCM, PBKDF2), errors, helper R2
│   ├── clients/openrouter.ts # fetch tipis ke OpenRouter (di-mock di test)
│   └── features/<fitur>/     # auth, account, ai-key, files, backup, sync
│       ├── routes.ts         # Hono + validator, tanpa logika bisnis
│       ├── service.ts        # logika bisnis, dependency lewat parameter
│       ├── repo.ts           # query Drizzle
│       └── *.ts (pure)       # aturan murni (mis. sync/merge.ts), tanpa I/O
└── test/
    ├── unit/                 # aturan murni
    ├── integration/          # exports.default.fetch per fitur + helper login
    ├── fixtures/contract/    # JSON request/response, dibaca juga oleh test Dart
    └── setup.ts              # applyD1Migrations, MSW (@msw/cloudflare)
```

Lapisan per fitur dan titik test:

```mermaid
flowchart TB
  subgraph feature["features/fitur"]
    RT["routes.ts<br/>Hono + zod, tanpa logika"] --> SV["service.ts<br/>logika bisnis"]
    SV --> PURE["aturan murni<br/>mis. sync/merge.ts"]
    SV --> RP["repo.ts<br/>Drizzle"]
  end
  SV --> CL["clients/openrouter.ts"]
  SV --> LIB["lib/: crypto · r2 · errors"]
  RP --> D1[(D1)]
  LIB --> R2[(R2)]
  CL --> OR[OpenRouter]
  TU["test/unit"] -.-> PURE
  TU -.-> SV
  TI["test/integration<br/>exports.default.fetch + MSW"] -.-> RT
```

Pipeline request (route `/v1/auth/*` milik Better Auth tidak lewat `session`):

```mermaid
flowchart LR
  R([Request]) --> A[requestId] --> B{killSwitch<br/>fitur nyala?}
  B -- tidak --> X1[503 + Retry-After]
  B -- ya --> C{bodyLimit}
  C -- kebesaran --> X2[413]
  C -- ok --> D{session<br/>Bearer valid?}
  D -- tidak --> X3[401]
  D -- ya --> E{rateLimit}
  E -- lewat batas --> X4[429 + Retry-After]
  E -- ok --> F{validator zod}
  F -- invalid --> X5[400]
  F -- ok --> H[handler<br/>routes → service → repo]
  H --> OK([Response])
  H -. throw .-> ERR[onError<br/>error seragam]
```

- **Urutan middleware**: `requestId → killSwitch → bodyLimit → session → rateLimit → validator → handler`, `onError` di luar. Saklar darurat jalan sebelum D1/R2 disentuh.
- **Validasi**: `@hono/zod-validator` + zod di semua input. Error seragam `{"error": {"code", "message"}}`; Flutter memetakan `code` ke enum.
- **Tanpa OpenAPI / codegen client Dart**: ±15 endpoint, fixture kontrak cukup. Ditinjau ulang kalau frontend web (#208) jalan.
- **Ukuran script**: Workers free maks 3MB terkompres; dicek lewat `wrangler deploy --dry-run` sejak #198.
- **`seq` sync per user** di `user_storage.seq`, dinaikkan di `db.batch()` yang sama dengan upsert record (D1 batch atomik).
- **Alat cek cepat**: Hono CLI (`npx hono request` / `batch`) boleh dipakai untuk eksplorasi; bukti tetap test vitest.

### Konvensi penamaan

| Lapisan | Format | Contoh |
|---|---|---|
| Tabel & kolom D1 | `snake_case`, tabel jamak | `users`, `ai_keys`, `user_id`, `expires_at` |
| Property TypeScript (Drizzle) | `camelCase` | `userId`, `expiresAt` |
| JSON request/response | `camelCase` | `{"keyHash": "…", "expiresAt": "…"}` |
| Kode error | `UPPER_SNAKE_CASE` | `QUOTA_EXCEEDED`, `INVALID_INVITE_CODE` |
| Path URL | huruf kecil, `kebab-case` | `/v1/ai/key`, `/v1/sync/push` |
| Waktu di JSON | ISO 8601 UTC | `"2026-11-12T15:04:05.123Z"` |
| Waktu / boolean di D1 | integer (`timestamp_ms` / `boolean` mode Drizzle) | `expires_at = 1794500000000` |

- Mapping `camelCase` ↔ `snake_case` lewat opsi `casing: "snake_case"` di `drizzle()` dan `drizzle.config.ts`; kode tidak menulis nama kolom satu-satu.
- **Jebakan Better Auth**: schema hasil generate bisa menulis nama kolom eksplisit (`text("emailVerified")`) yang menang atas `casing`. Habis generate, nama kolom diubah ke `snake_case`, property dibiarkan (Better Auth memetakan lewat property). Test integrasi auth membuktikan.
- JSON `camelCase` karena respons Better Auth sudah `camelCase` dan Dart (`freezed` + `json_serializable`) default `camelCase`, jadi tanpa `@JsonKey(name:)`.
- Kode error ikut format Better Auth (`INVALID_EMAIL_OR_PASSWORD`), satu pola di client.
- `records.data` (sync) memakai nama field Dart (`camelCase`), bukan nama kolom SQL Drift.

### Schema D1

Tabel `users`, `sessions`, `accounts`, `verifications` dibuat Better Auth (`npx auth@latest generate`, `usePlural: true`); sisanya milik Luma.

```mermaid
erDiagram
  users ||--o{ sessions : punya
  users ||--o{ accounts : "login lewat"
  users ||--o| ai_keys : "key subsidi"
  users ||--|| user_storage : "kuota + seq"
  users ||--o{ records : "data sync"
  invite_codes }o--o| users : dipakai
  users {
    text id PK
    text email
    text name
    int email_verified
    int banned
    int created_at
    int updated_at
  }
  sessions {
    text id PK
    text user_id FK
    text token
    int expires_at
  }
  accounts {
    text id PK
    text user_id FK
    text provider_id
    text account_id
  }
  verifications {
    text id PK
    text identifier
    int expires_at
  }
  invite_codes {
    text code PK
    text used_by FK
    int used_at
  }
  ai_keys {
    text user_id PK, FK
    text key_hash
    text key_enc
    real limit_usd
    int expires_at
  }
  user_storage {
    text user_id PK, FK
    int bytes
    int seq
  }
  records {
    text user_id PK, FK
    text kind PK
    text key PK
    text data
    int updated_at
    int deleted
    int seq
  }
```

## Strategi test

Tiap issue backend selesai bawa test-nya di semua lapisan yang disentuh. Integrasi Workers memakai `@cloudflare/vitest-plugin` (`cloudflareTest()`, pengganti `@cloudflare/vitest-pool-workers`; Vitest di runtime workerd, D1/R2/rate limit lokal Miniflare). Request ke Worker lewat `exports.default.fetch` dari `cloudflare:workers` (`SELF` sudah deprecated). `fetchMock` dari `cloudflare:test` sudah dihapus: mock keluar (Google, OpenRouter) lewat **MSW** dengan `@msw/cloudflare` (`msw/node` gak jalan di workerd). `test/setup.ts` memasang handler cadangan: fetch keluar yang gak di-mock dapat 599 `UNMOCKED_FETCH`, jadi subrequest tak terduga ketahuan.

| Lapisan | Alat | Isi | Perintah |
|---|---|---|---|
| Unit backend | vitest | Aturan murni: merge sync per kind, retensi backup, hitung limit, nama key R2, crypto | `make backend-test` |
| Integrasi backend | `exports.default.fetch` / `app.request` + D1/R2 lokal, migrasi `applyD1Migrations` | Tiap endpoint lewat app utuh, layanan luar di-mock | `make backend-test` |
| Kontrak | `test/fixtures/contract/*.json` | Contoh request/response asli, dibaca vitest dan test Dart | dua-duanya |
| Unit/data Flutter | `flutter test` | Mapping kunci alami, trigger outbox (Drift in-memory), service HTTP pakai adapter `dio` palsu | `make test` |
| Widget Flutter | `flutter test` | Login, Pengaturan, banner; provider di-override (aturan `CLAUDE.md`) | `make test` |
| E2E lokal (#109 saja) | test Dart bertag `backend` ke `wrangler dev` | Dua `AppDatabase` in-memory sync lewat Worker lokal; default di-skip | `make backend-e2e` |

**Checklist wajib tiap endpoint** (integrasi):

1. Jalur sukses.
2. 401 tanpa token / token salah.
3. 400 / 413 body tidak valid atau kebesaran.
4. Isolasi user: user A tidak bisa baca/tulis data user B.
5. Saklar darurat mati → 503, D1/R2 tidak disentuh.
6. 429 saat kena rate limit.
7. Anggaran: jumlah query D1 dan subrequest per request ≤ [tabel anggaran](#anggaran-per-aksi) (spy di `env.DB` / `fetch`).

**Coverage**: `@vitest/coverage-istanbul` (V8 tidak didukung di pool Workers), ambang 80% baris untuk `service.ts` dan file aturan murni; `routes.ts` cukup lewat integrasi. CPU 10ms tidak terukur di test: dicek lewat `wrangler dev` dan Workers Logs env dev.

E2E hanya diwajibkan di #109; fase lain cukup unit + integrasi + kontrak + test Flutter.

## Alur kerja per issue

Tiap issue dikerjakan utuh per fitur (vertical slice), bukan semua backend dulu lalu semua Flutter:

1. **Kontrak dulu**: contoh request/response ditulis di `apps/backend/test/fixtures/contract/` sebelum kode. Backend dan Flutter sama-sama dites terhadap file itu.
2. **Backend**: endpoint + test (unit, integrasi, kontrak), `make backend-test`, deploy `make backend-deploy e=dev`.
3. **Flutter**: service → repository / ViewModel → UI, dengan test-nya. UI yang board desainnya belum ada menyusul; backend + service jalan duluan.
4. **Cek ujung ke ujung**: `make backend-live` + coba di Luma Dev.
5. **Merge** branch issue ke `feat/backend`, **push** `feat/backend` ke GitHub (backup, tanpa PR ke `master`), tutup issue dengan ringkasan cek yang dijalankan.

## Branch & worktree

```mermaid
%%{init: {'gitGraph': {'mainBranchName': 'master'}}}%%
gitGraph
  commit id: "app stabil"
  branch feat/backend
  commit id: "docs backend"
  branch issue-198
  commit id: "scaffold"
  checkout feat/backend
  merge issue-198
  checkout master
  commit id: "fix app"
  checkout feat/backend
  merge master id: "sinkron master"
  branch issue-199
  commit id: "auth"
  checkout feat/backend
  merge issue-199
  checkout master
  merge feat/backend id: "MVP backend"
```

- Semua kerja backend di branch **`feat/backend`** (worktree terpisah, dibuat dari `master`). Tiap issue punya branch sendiri dari `feat/backend` dan di-merge ke sana, bukan ke `master`.
- `master` di-merge ke `feat/backend` tiap mulai issue baru supaya tidak makin jauh.
- Build hanya Luma Dev (`make dev`, `make run f=dev`); app Luma tidak tersentuh sampai merge.
- **Schema Drift**: migrasi backend (#109) selalu memakai nomor setelah `schemaVersion` terbaru di `master`. Kalau `master` naik schema setelah migrasi backend dibuat, nomor dan test migrasinya disesuaikan saat merge `master` → `feat/backend`.
- `feat/backend` di-merge ke `master` setelah #198–#201, #109, dan #210 selesai dan diuji di device.

## Setup & deploy

Sekali per akun Cloudflare (butuh `make backend-install` dulu):

```bash
cd apps/backend
bunx wrangler login
bunx wrangler d1 create luma-dev        # salin database_id ke env.dev di wrangler.jsonc
bunx wrangler d1 create luma-prod       # → env.prod
bunx wrangler r2 bucket create luma-dev
bunx wrangler r2 bucket create luma-prod
```

Lalu:

1. Isi `database_id` dev/prod di `wrangler.jsonc`, `make backend-types`.
2. `make backend-migrate e=dev` (setelah ada migrasi, mulai #199).
3. `make backend-deploy e=dev`. URL per env ada di `backendUrls` (`apps/mobile/lib/data/services/backend_client.dart`).
4. Cek: `make backend-live` (client Flutter → Worker dev) atau `curl https://luma-backend-dev.choiruladamm.workers.dev/v1/health` → `{"status":"ok","env":"dev"}`. Tepat setelah deploy pertama ke subdomain baru, beberapa request bisa kena error Cloudflare 1104/1042 selama propagasi; hilang sendiri dalam ±1 menit.

**Status resource** (12 November 2026): env dev udah dibuat dan ter-deploy (D1 `luma-dev`, R2 `luma-dev`, `https://luma-backend-dev.choiruladamm.workers.dev`). Env prod (D1/R2 `luma-prod`) dibuat saat backend di-merge ke `master`.

Secret (tiap env): `bunx wrangler secret put <NAMA> --env dev`. Lokal: salin `apps/backend/.dev.vars.example` ke `.dev.vars` (gitignored). Secret gak pernah ditulis di `wrangler.jsonc`. Dibutuhkan: `BETTER_AUTH_SECRET` (`openssl rand -base64 32`; dev udah diisi), `GOOGLE_CLIENT_SECRET` (#199, Google).

Harian:

| Perintah | Fungsi |
|---|---|
| `make backend-dev` | Worker lokal env dev di `:8787` (D1/R2 lokal). Dari device: `make run f=dev` dengan `--dart-define=BACKEND_URL=http://<ip-laptop>:8787` |
| `make backend-test` | Typecheck + vitest (workerd) + coverage ≥ 80% |
| `make backend-live` | Client Flutter memanggil Worker dev yang ter-deploy (jaringan) |
| `make backend-types` | Generate ulang tipe `Env` setelah ubah `wrangler.jsonc` |
| `make backend-migrate e=dev` | Terapkan migrasi D1 remote |
| `make backend-deploy e=dev` | Deploy; `e=prod` cuma dari `master` |

Ukuran bundle dicek `bunx wrangler deploy --env dev --dry-run --outdir dist` (scaffold #198: 16,5 KiB gzip, batas 3MB).

## Urutan kerja

1. Scaffold `apps/backend` ([#198](https://github.com/choiruladamm/luma/issues/198), Hono, Drizzle, D1, R2, env dev/prod, observability, vitest, target Makefile)
2. Auth backend + data layer ([#199](https://github.com/choiruladamm/luma/issues/199), email dev, kode undangan, sesi, hapus akun, `/privacy`)
   - Auth UI + Google ([#211](https://github.com/choiruladamm/luma/issues/211), layar Masuk, akun di Pengaturan, gerbang login wajib; nunggu board desain + OAuth Client ID). Boleh dikerjakan paralel dengan #200–#201.
3. Key AI ([#200](https://github.com/choiruladamm/luma/issues/200), subsidi + BYOK, guardrail, budget)
4. Backup cloud ([#201](https://github.com/choiruladamm/luma/issues/201))
5. Sync push ([#109](https://github.com/choiruladamm/luma/issues/109), migrasi outbox/inbox, push, dump Markdown)
6. Sync pull ([#210](https://github.com/choiruladamm/luma/issues/210), pull, inbox, download buku, E2E dua device)

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
