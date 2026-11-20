// Generates random invite codes and stores them in remote D1: `make backend-invite e=dev n=3`.
// The printed code is what you hand out; the stored one is its normalized form.
import { newInviteCode, normalizeInviteCode } from "@luma/core/auth/invite";

const [envName, count = "1"] = process.argv.slice(2);
if (envName !== "dev" && envName !== "prod")
  throw new Error("pakai: bun scripts/invite.ts dev|prod [jumlah]");

const codes = Array.from({ length: Number(count) }, newInviteCode);
const now = Date.now();
const values = codes.map((c) => `('${normalizeInviteCode(c)}', ${now})`).join(", ");
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
    "--command",
    `INSERT INTO invite_codes (code, created_at) VALUES ${values}`,
  ],
  { stdout: "ignore", stderr: "inherit" },
);
if (run.exitCode !== 0) process.exit(run.exitCode ?? 1);
console.log(codes.join("\n"));
