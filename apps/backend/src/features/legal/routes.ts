import { Hono } from "hono";
import { html } from "hono/html";
import type { AppEnv } from "../../env";

const CONTACT = "work.adamm@gmail.com";

const page = (title: string, body: ReturnType<typeof html>) => html`<!doctype html>
  <html lang="id">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>${title} · Luma</title>
      <style>
        body { font: 16px/1.6 system-ui, sans-serif; max-width: 42rem; margin: 2rem auto; padding: 0 1rem; color: #1d1d1f; background: #fffdf5; }
        h1, h2 { line-height: 1.25; }
        @media (prefers-color-scheme: dark) { body { color: #f2f2f2; background: #151515; } a { color: #ffd84d; } }
      </style>
    </head>
    <body>
      ${body}
    </body>
  </html>`;

/** Halaman statis yang diwajibkan App Store / Play Store (docs/backend.md, Sesi & akun). */
export const legal = new Hono<AppEnv>()
  .get("/privacy", (c) =>
    c.html(
      page(
        "Kebijakan privasi",
        html`<h1>Kebijakan privasi Luma</h1>
          <h2>Yang disimpan di server</h2>
          <ul>
            <li>Akun: nama, email, dan foto dari Google (atau email di build developer).</li>
            <li>Backup cloud: salinan database Luma dan file buku yang kamu impor.</li>
            <li>Data sync: posisi baca, terjemahan, Bedahin, sesi baca, dan riwayat chat buku.</li>
          </ul>
          <h2>Yang dikirim ke pihak lain</h2>
          <p>
            Teks paragraf yang kamu ketuk dan pertanyaan chat dikirim ke OpenRouter untuk
            diterjemahkan dan dijelaskan. Login Google diproses oleh Google.
          </p>
          <h2>Hapus akun</h2>
          <p>
            Hapus akun dari Pengaturan → Akun → Hapus akun, atau lihat
            <a href="/account/delete">cara hapus akun</a>. Semua data di server dihapus permanen.
          </p>
          <h2>Kontak</h2>
          <p><a href="mailto:${CONTACT}">${CONTACT}</a></p>
          <hr />
          <p lang="en">
            <strong>English:</strong> Luma stores your account, cloud backup, and sync data on
            Cloudflare. Tapped paragraphs and chat questions are sent to OpenRouter for translation.
            Delete your account in Settings → Account → Delete account, or email ${CONTACT}.
          </p>`,
      ),
    ),
  )
  .get("/account/delete", (c) =>
    c.html(
      page(
        "Hapus akun",
        html`<h1>Hapus akun Luma</h1>
          <ol>
            <li>Buka Luma → Pengaturan → Akun.</li>
            <li>Ketuk <strong>Hapus akun</strong>, lalu konfirmasi.</li>
          </ol>
          <p>
            Akun, backup cloud, dan data sync di server dihapus permanen. Data yang ada di HP
            tetap ada sampai aplikasinya kamu hapus.
          </p>
          <p>Gak bisa buka aplikasinya? Email <a href="mailto:${CONTACT}">${CONTACT}</a> dari alamat akunmu.</p>
          <hr />
          <p lang="en">
            <strong>English:</strong> Open Luma → Settings → Account → Delete account. Your account,
            cloud backups, and sync data are permanently deleted. Can't open the app? Email ${CONTACT}
            from your account address.
          </p>`,
      ),
    ),
  );
