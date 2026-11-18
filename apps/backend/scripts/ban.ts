// Revokes subsidized AI access for one user: `make backend-ban e=dev email=a@b.c`.
// The OpenRouter key is deleted first so a key already extracted from a device dies
// immediately instead of living out its 30-day expiry; then `banned` and the `ai_keys` row in D1.
// Needs the management key in the env: OPENROUTER_MANAGEMENT_KEY=... make backend-ban ...
import { openRouterAdmin } from "../src/clients/openrouter";

const [envName, email] = process.argv.slice(2);
if ((envName !== "dev" && envName !== "prod") || !email)
  throw new Error("pakai: bun scripts/ban.ts dev|prod <email>");
const managementKey = process.env.OPENROUTER_MANAGEMENT_KEY;
if (!managementKey)
  throw new Error("OPENROUTER_MANAGEMENT_KEY belum diisi (management key workspace env ini)");

const d1 = <T = Record<string, unknown>>(sql: string): T[] => {
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
      sql,
    ],
    {
      stderr: "inherit",
    },
  );
  if (run.exitCode !== 0) process.exit(run.exitCode ?? 1);
  const parsed: { results: T[] }[] = JSON.parse(run.stdout.toString());
  return parsed[0]?.results ?? [];
};

const quoted = `'${email.replaceAll("'", "''")}'`;
const [user] = d1<{ id: string; hash: string | null }>(
  `SELECT users.id AS id, ai_keys.key_hash AS hash FROM users LEFT JOIN ai_keys ON ai_keys.user_id = users.id WHERE users.email = ${quoted}`,
);
if (!user) throw new Error(`user ${email} gak ada di ${envName}`);

if (user.hash) await openRouterAdmin(managementKey).deleteKey(user.hash);
d1(
  `UPDATE users SET banned = 1 WHERE id = '${user.id}'; DELETE FROM ai_keys WHERE user_id = '${user.id}'`,
);
console.log(`${email}: banned, key ${user.hash ?? "(belum ada)"} dicabut`);
