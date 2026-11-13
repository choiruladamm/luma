// Bikin kode undangan acak dan simpan ke D1 remote: `make backend-invite e=dev n=3`.
// Kode yang dicetak = yang dikasih ke orang; yang disimpan = bentuk normalisasinya.
import { newInviteCode, normalizeInviteCode } from "../src/auth/invite";

const [envName, count = "1"] = process.argv.slice(2);
if (envName !== "dev" && envName !== "prod") throw new Error("pakai: bun scripts/invite.ts dev|prod [jumlah]");

const codes = Array.from({ length: Number(count) }, newInviteCode);
const values = codes.map((c) => `('${normalizeInviteCode(c)}')`).join(", ");
const run = Bun.spawnSync(
  ["bunx", "wrangler", "d1", "execute", "DB", "--env", envName, "--remote", "--command", `INSERT INTO invite_codes (code) VALUES ${values}`],
  { stdout: "ignore", stderr: "inherit" },
);
if (run.exitCode !== 0) process.exit(run.exitCode ?? 1);
console.log(codes.join("\n"));
