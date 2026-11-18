// Restores subsidized AI access for one user: `make backend-unban e=dev email=a@b.c`.
// Only sets `banned = 0`; a new key is created lazily when the app calls `POST /v1/ai/key` again.
// Terminal fallback for when the admin dashboard is unavailable.
const [envName, email] = process.argv.slice(2);
if ((envName !== "dev" && envName !== "prod") || !email)
  throw new Error("pakai: bun scripts/unban.ts dev|prod <email>");

const quoted = `'${email.replaceAll("'", "''")}'`;
const run = Bun.spawnSync(
  [
    "bunx",
    "wrangler",
    "d1",
    "execute",
    "DB",
    "--env",
    envName,
    "--remote",
    "--json",
    "--command",
    `UPDATE users SET banned = 0 WHERE email = ${quoted} RETURNING id`,
  ],
  { stderr: "inherit" },
);
if (run.exitCode !== 0) process.exit(run.exitCode ?? 1);
const parsed: { results: { id: string }[] }[] = JSON.parse(run.stdout.toString());
const [user] = parsed[0]?.results ?? [];
if (!user) throw new Error(`user ${email} gak ada di ${envName}`);
console.log(`${email}: unbanned`);
