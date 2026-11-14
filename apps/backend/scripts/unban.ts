// Pulihkan akses AI subsidi satu user: `make backend-unban e=dev email=a@b.c`.
// Cuma `banned = 0`; key baru dibuat lazy waktu app minta `POST /v1/ai/key` lagi.
// Cadangan terminal kalau dashboard admin gak bisa dipakai.
const [envName, email] = process.argv.slice(2);
if ((envName !== "dev" && envName !== "prod") || !email) throw new Error("pakai: bun scripts/unban.ts dev|prod <email>");

const quoted = `'${email.replaceAll("'", "''")}'`;
const run = Bun.spawnSync(
  ["bunx", "wrangler", "d1", "execute", "DB", "--env", envName, "--remote", "--json", "--command", `UPDATE users SET banned = 0 WHERE email = ${quoted} RETURNING id`],
  { stderr: "inherit" },
);
if (run.exitCode !== 0) process.exit(run.exitCode ?? 1);
const [user] = JSON.parse(run.stdout.toString())[0].results as { id: string }[];
if (!user) throw new Error(`user ${email} gak ada di ${envName}`);
console.log(`${email}: unbanned`);
