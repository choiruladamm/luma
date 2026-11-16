import { Hono } from "hono";
import { html } from "hono/html";
import type { AppEnv } from "../../env";

const CONTACT = "work.adamm@gmail.com";
/** Bump when the content of either page changes. */
const LAST_UPDATED = "November 16, 2026";

// Same mark as the app and the admin dashboard (yellow stabilo U, pink dot).
const LOGO = html`<svg viewBox="0 0 100 100" width="36" height="36" fill="none" aria-hidden="true">
  <path d="M26 34 C26 72, 74 72, 74 34" transform="translate(4 4)" stroke="#1A1A1A" stroke-width="28" stroke-linecap="square" />
  <path d="M26 34 C26 72, 74 72, 74 34" stroke="#1A1A1A" stroke-width="28" stroke-linecap="square" />
  <path d="M26 34 C26 72, 74 72, 74 34" stroke="#FFD84D" stroke-width="20" stroke-linecap="square" />
  <circle cx="50" cy="22" r="9" fill="#FFC2D3" stroke="#1A1A1A" stroke-width="4" />
</svg>`;

// Stabilo tokens (board "14 · Admin web"): light from the board, dark from the app's dark set.
const STYLE = html`<style>
  :root {
    color-scheme: light dark;
    --page: #f2eddd; --sheet: #fffdf5; --ink: #1c1c1c; --ink2: #5e5a4e; --line: #e4ddc9;
    --accent: #ffd84d; --pink: #ffc2d3; --on-mark: #1a1a1a;
  }
  @media (prefers-color-scheme: dark) {
    :root { --page: #22201c; --sheet: #2c2a25; --ink: #ddd7c8; --ink2: #a19b8e; --line: #46423a; --accent: #e9c75a; --pink: #d99bae; --on-mark: #22201c; }
  }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--page); color: var(--ink); font: 16px/1.65 ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif; -webkit-text-size-adjust: 100%; }
  .wrap { max-width: 60rem; margin: 0 auto; padding: 24px 16px 48px; }
  header { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-bottom: 20px; }
  .brand { display: flex; align-items: center; gap: 8px; color: var(--ink); text-decoration: none; font-weight: 700; font-size: 18px; }
  nav { display: flex; gap: 4px; flex-wrap: wrap; }
  nav a { padding: 6px 12px; border-radius: 999px; color: var(--ink2); text-decoration: none; font-size: 14px; font-weight: 500; }
  nav a:hover { color: var(--ink); background: var(--line); }
  nav a[aria-current="page"] { background: var(--ink); color: var(--page); }
  main { background: var(--sheet); border-radius: 24px; padding: 28px 24px 32px; }
  h1 { margin: 0 0 4px; font-size: clamp(26px, 6vw, 34px); line-height: 1.2; letter-spacing: -0.01em; }
  .updated { margin: 0 0 20px; color: var(--ink2); font-size: 14px; }
  .lead { font-size: 17px; }
  h2 { margin: 32px 0 8px; font-size: 20px; line-height: 1.3; }
  h3 { margin: 20px 0 4px; font-size: 16px; }
  p, ul, ol { margin: 8px 0; }
  ul, ol { padding-left: 1.3em; }
  li { margin: 4px 0; }
  a { color: inherit; text-decoration-color: var(--accent); text-decoration-thickness: 2px; text-underline-offset: 3px; }
  mark { background: linear-gradient(transparent 55%, var(--accent) 55%); color: inherit; }
  @media (prefers-color-scheme: dark) { mark { background: var(--accent); color: var(--on-mark); border-radius: 3px; } }
  .note { margin: 20px 0; padding: 14px 16px; border-radius: 16px; background: var(--page); }
  .steps { counter-reset: step; list-style: none; padding: 0; }
  .steps li { counter-increment: step; display: flex; gap: 12px; align-items: baseline; margin: 10px 0; }
  .steps li::before { content: counter(step); flex: none; width: 28px; height: 28px; border-radius: 999px; background: var(--accent); color: var(--on-mark); font-weight: 700; display: inline-flex; align-items: center; justify-content: center; font-size: 14px; }
  table { width: 100%; border-collapse: collapse; margin: 8px 0; font-size: 15px; }
  th, td { text-align: left; vertical-align: top; padding: 10px 8px; border-bottom: 1px solid var(--line); }
  th { color: var(--ink2); font-weight: 500; font-size: 14px; }
  td:first-child { font-weight: 600; }
  @media (min-width: 900px) { .wrap { padding: 40px 32px 64px; } main { padding: 44px 56px 52px; border-radius: 28px; } td:first-child { white-space: nowrap; padding-right: 20px; } td:last-child { width: 26%; } }
  footer { margin-top: 20px; color: var(--ink2); font-size: 14px; text-align: center; }
  @media (max-width: 520px) { main { padding: 22px 16px 26px; border-radius: 20px; } th, td { padding: 8px 4px; } }
</style>`;

type Page = "privacy" | "delete";

const page = (current: Page, title: string, body: ReturnType<typeof html>) => html`<!doctype html>
  <html lang="en">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>${title} · Luma</title>
      <meta name="description" content="${title} for Luma, the book reader with tap-to-translate." />
      ${STYLE}
    </head>
    <body>
      <div class="wrap">
        <header>
          <a class="brand" href="/privacy">${LOGO}<span>Luma</span></a>
          <nav aria-label="Legal">
            <a href="/privacy" ${current === "privacy" ? html`aria-current="page"` : ""}>Privacy</a>
            <a href="/account/delete" ${current === "delete" ? html`aria-current="page"` : ""}>Delete account</a>
          </nav>
        </header>
        <main>${body}</main>
        <footer>Questions? <a href="mailto:${CONTACT}">${CONTACT}</a></footer>
      </div>
    </body>
  </html>`;

const privacy = html`<h1>Privacy Policy</h1>
  <p class="updated">Last updated ${LAST_UPDATED}</p>
  <p class="lead">
    Luma is a book reader for EPUB, Markdown, and PDF files: tap a paragraph to get an Indonesian
    translation and its meaning. Luma is <mark>local-first</mark>: your books and reading data live on
    your phone. An account adds cloud backup, sync between your phones, and a free AI allowance. This
    page explains what reaches our servers, who else sees it, and how to delete it.
  </p>

  <h2>What stays on your phone</h2>
  <ul>
    <li>Your books and everything about them, unless you turn on cloud backup or sync (below).</li>
    <li>
      Your own OpenRouter API key, if you add one. It is kept in the phone's secure storage and is
      never sent to Luma's servers.
    </li>
  </ul>

  <h2>What we store on our servers</h2>
  <table>
    <thead>
      <tr><th>Data</th><th>What it is</th><th>Why</th></tr>
    </thead>
    <tbody>
      <tr><td>Account</td><td>Name, email address, and profile photo from your Google account, plus Google's account ID (developer test builds use an email and password instead; the password is stored only as a hash)</td><td>Sign-in and identifying your data</td></tr>
      <tr><td>Sign-in sessions</td><td>Session token, IP address, app version and device type (user agent), and when the session was created and last used</td><td>Keeping you signed in; security</td></tr>
      <tr><td>Cloud backup</td><td>A copy of Luma's database and the book files you imported, when you back up</td><td>Restoring your library on a new phone</td></tr>
      <tr><td>Sync data</td><td>Reading positions, translations and explanations, reading sessions, and book chat history</td><td>Keeping your phones in step</td></tr>
      <tr><td>Usage counters</td><td>Storage used and sync writes per day</td><td>Fair-use limits</td></tr>
      <tr><td>Free AI key</td><td>An OpenRouter key issued for your account, stored encrypted, with its daily limit</td><td>The free AI allowance</td></tr>
      <tr><td>Invite code</td><td>The code you signed up with and when</td><td>Beta access</td></tr>
    </tbody>
  </table>
  <p>We don't run ads or sell your data.</p>

  <h2>Who else processes your data</h2>
  <h3>OpenRouter (AI)</h3>
  <p>
    When you tap a paragraph or ask about a book, that text is sent <strong>directly from your phone</strong>
    to <a href="https://openrouter.ai/privacy">OpenRouter</a>, which routes it to an AI model provider to
    produce the translation or answer. With your own key, this happens under your OpenRouter account;
    with the free allowance, under the key Luma issued for you. Luma's servers don't see this text.
  </p>
  <h3>Google (sign-in)</h3>
  <p>
    Sign-in uses <a href="https://policies.google.com/privacy">Google</a>. Google shares your name, email
    address, and profile photo with Luma.
  </p>
  <h3>Cloudflare (hosting)</h3>
  <p>
    Luma's servers, database, and file storage run on <a href="https://www.cloudflare.com/privacypolicy/">Cloudflare</a>.
    Cloudflare keeps request logs (such as IP address, time, and the address requested) for a few days.
  </p>

  <h2>How long we keep it</h2>
  <p>
    Everything in "What we store" stays until you delete your account. Deleting it removes your data
    from the database and file storage right away and revokes your free AI key. Request logs expire on
    their own within a few days.
  </p>

  <h2>Security</h2>
  <p>
    All traffic is encrypted (HTTPS). Free AI keys are encrypted at rest. Session tokens on your phone
    are kept in secure storage.
  </p>

  <h2>Your choices</h2>
  <ul>
    <li><strong>Use Luma without backup or sync</strong>: your books then stay on your phone only.</li>
    <li><strong>Use your own AI key</strong> instead of the free allowance.</li>
    <li><strong>Delete your account</strong> and all server data at any time: <a href="/account/delete">here's how</a>.</li>
    <li><strong>Ask</strong> what we hold about you, or for a correction, by emailing <a href="mailto:${CONTACT}">${CONTACT}</a>.</li>
  </ul>

  <h2>Children</h2>
  <p>Luma is not directed at children under 13, and we don't knowingly collect their data.</p>

  <h2>Changes</h2>
  <p>
    If this policy changes, we update this page and the date at the top.
  </p>

  <h2>Contact</h2>
  <p><a href="mailto:${CONTACT}">${CONTACT}</a></p>`;

const deleteAccount = html`<h1>Delete your Luma account</h1>
  <p class="updated">Last updated ${LAST_UPDATED}</p>
  <p class="lead">You can delete your account and all of its data on our servers at any time, right from the app.</p>

  <h2>In the app</h2>
  <ol class="steps">
    <li><span>Open Luma and go to <strong>Settings → Account</strong>.</span></li>
    <li><span>Tap <strong>Delete account</strong>.</span></li>
    <li><span>Tick the three boxes, then tap <strong>Delete account forever</strong>.</span></li>
  </ol>
  <p>Deletion happens immediately. It can't be undone.</p>

  <h2>What gets deleted</h2>
  <ul>
    <li>Your account (name, email, profile photo) and all sign-in sessions</li>
    <li>All cloud backups, including uploaded book files</li>
    <li>All sync data: reading positions, translations and explanations, reading sessions, and book chat history</li>
    <li>Your free AI key (revoked at OpenRouter) and usage counters</li>
  </ul>

  <h2>What stays</h2>
  <ul>
    <li>
      <strong>Books on your phone.</strong> They stay until you remove them or uninstall Luma, but
      won't be backed up or synced anymore.
    </li>
    <li><strong>Request logs</strong> at our hosting provider, which expire on their own within a few days.</li>
    <li>The invite code you used stays marked as used, with no link to you.</li>
  </ul>

  <div class="note">
    <strong>Can't open the app?</strong> Email <a href="mailto:${CONTACT}?subject=Delete%20my%20Luma%20account">${CONTACT}</a>
    from the email address of your Luma account and ask for deletion. We delete everything listed above
    within 30 days and reply to confirm.
  </div>

  <p>More about the data Luma keeps: <a href="/privacy">Privacy Policy</a>.</p>`;

/** Static pages the App Store and Play Store require (docs/backend.md, Sesi & akun). */
export const legal = new Hono<AppEnv>()
  .get("/privacy", (c) => c.html(page("privacy", "Privacy Policy", privacy)))
  .get("/account/delete", (c) => c.html(page("delete", "Delete your account", deleteAccount)));
