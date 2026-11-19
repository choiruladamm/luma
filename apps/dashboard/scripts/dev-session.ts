// `make dashboard-dev-session`: lets an agent (agent-browser) into luma-admin-dev without Google.
// Inserts a 1-day session for the dev admin straight into the dev D1 and writes what a browser
// needs into .wrangler/dev-session/ (gitignored): the Access service-token headers and the signed
// session cookie. Dev only; reads .dev.vars.remote-dev (gitignored). Rules: docs/dashboard.md
// (Access and sessions and request guards).
import { execFileSync } from "node:child_process";
import { createHmac, randomBytes } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";

const vars = Object.fromEntries(
  readFileSync(".dev.vars.remote-dev", "utf8")
    .split("\n")
    .filter((line) => /^[A-Z_]+=/.test(line))
    .map((line) => [line.slice(0, line.indexOf("=")), line.slice(line.indexOf("=") + 1).trim()]),
);
for (const key of [
  "CF_ACCESS_CLIENT_ID",
  "CF_ACCESS_CLIENT_SECRET",
  "BETTER_AUTH_SECRET",
  "ADMIN_EMAIL",
]) {
  if (!vars[key]) throw new Error(`${key} missing in .dev.vars.remote-dev`);
}

const now = Date.now();
const token = randomBytes(16).toString("hex");
const email = vars.ADMIN_EMAIL.replaceAll("'", "''");
// One request: drop expired sessions from this script, then add one for the admin.
const sql = [
  `DELETE FROM sessions WHERE user_agent = 'dev-session' AND expires_at < ${now};`,
  `INSERT INTO sessions (id,expires_at,token,created_at,updated_at,user_id,user_agent)
   SELECT 'dev-session-${token}', ${now + 86_400_000}, '${token}', ${now}, ${now}, id, 'dev-session'
   FROM users WHERE lower(email) = lower('${email}');`,
].join("\n");
const out = execFileSync(
  "bunx",
  ["wrangler", "d1", "execute", "DB", "--env", "dev", "--remote", "--json", "--command", sql],
  { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] },
);
if (!/"changes":\s*1\b/.test(out.slice(out.lastIndexOf('"meta"')))) {
  throw new Error(`no user ${vars.ADMIN_EMAIL} in the dev D1`);
}

const signature = createHmac("sha256", vars.BETTER_AUTH_SECRET).update(token).digest("base64");
mkdirSync(".wrangler/dev-session", { recursive: true });
writeFileSync(
  ".wrangler/dev-session/headers.json",
  JSON.stringify({
    "CF-Access-Client-Id": vars.CF_ACCESS_CLIENT_ID,
    "CF-Access-Client-Secret": vars.CF_ACCESS_CLIENT_SECRET,
  }),
);
writeFileSync(
  ".wrangler/dev-session/cookies.json",
  JSON.stringify([
    {
      name: "__Secure-better-auth.session_token",
      value: encodeURIComponent(`${token}.${signature}`),
      // A `__Secure-` cookie is rejected unless it is marked secure.
      domain: "luma-admin-dev.chrl.cloud",
      path: "/",
      secure: true,
      httpOnly: true,
      sameSite: "Lax",
    },
  ]),
);
console.log(
  "Session valid 24h. Files in apps/dashboard/.wrangler/dev-session/ (see docs/dashboard.md).",
);
