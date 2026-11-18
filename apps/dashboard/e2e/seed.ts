// Seed for the local e2e D1 (never a remote database). Keys stay off the seeded users so
// ban/unban never calls OpenRouter.
export const ADMIN_TOKEN = "e2eadmintoken000000000000000000a";
const DAY = 86_400_000;

export const SEED_USERS = [
  { id: "e2e-1", email: "rara.anindya@e2e.local", name: "Rara Anindya" },
  { id: "e2e-2", email: "sekar.ayu@e2e.local", name: "Sekar Ayu" },
  { id: "e2e-3", email: "bayu.w@e2e.local", name: "Bayu Wicaksono", banned: true },
  { id: "e2e-4", email: "nadia.halim@e2e.local", name: "Nadia Halim" },
];

export function seedSql(now: number) {
  const q = (s: string) => `'${s.replaceAll("'", "''")}'`;
  const lines = [
    ...[
      "records",
      "ai_keys",
      "user_storage",
      "invite_codes",
      "sessions",
      "accounts",
      "verifications",
      "users",
    ].map((t) => `DELETE FROM ${t};`),
    `INSERT INTO users (id,name,email,email_verified,created_at,updated_at,banned) VALUES ('e2e-admin','E2E Admin','admin@e2e.local',1,${now - 30 * DAY},${now},0);`,
    `INSERT INTO sessions (id,expires_at,token,created_at,updated_at,user_id) VALUES ('e2e-admin-s',${now + 12 * 3_600_000},${q(ADMIN_TOKEN)},${now},${now},'e2e-admin');`,
  ];
  SEED_USERS.forEach((u, i) => {
    const created = now - (i + 1) * DAY;
    lines.push(
      `INSERT INTO users (id,name,email,email_verified,created_at,updated_at,banned) VALUES (${q(u.id)},${q(u.name)},${q(u.email)},1,${created},${created},${u.banned ? 1 : 0});`,
      `INSERT INTO accounts (id,account_id,provider_id,user_id,created_at,updated_at) VALUES (${q(`${u.id}-a`)},${q(`g-${u.id}`)},'google',${q(u.id)},${created},${created});`,
      `INSERT INTO sessions (id,expires_at,token,created_at,updated_at,user_id,user_agent) VALUES (${q(`${u.id}-s`)},${now + 50 * DAY},${q(`tok-${u.id}`)},${created},${now - i * 3_600_000},${q(u.id)},'Luma/0.3.0 (+mailto:x)');`,
      `INSERT INTO user_storage (user_id,bytes,seq,sync_bytes,sync_day,sync_rows) VALUES (${q(u.id)},${(i + 1) * 50 * 1024 * 1024},1,${(i + 1) * 100 * 1024},${Math.floor(now / DAY)},${(i + 1) * 1000});`,
      `INSERT INTO invite_codes (code,used_by,used_at,created_at) VALUES (${q(`LUMA-USED${i}-E2E00`)},${q(u.id)},${created},${created - DAY});`,
    );
  });
  lines.push(
    `INSERT INTO invite_codes (code,created_at) VALUES ('LUMA-FREE0-E2E00',${now - DAY}), ('LUMA-FREE1-E2E00',${now});`,
  );
  return lines.join("\n");
}
