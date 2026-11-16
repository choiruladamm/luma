import { execFileSync } from "node:child_process";
import { createHmac } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { seedSql, ADMIN_TOKEN } from "./seed";

const STATE = ".wrangler/e2e-state";
const wrangler = (...args: string[]) =>
  execFileSync("bunx", ["wrangler", "d1", ...args, "--env", "e2e", "--local", "--persist-to", STATE], { stdio: "pipe" });

/**
 * Fresh data for every run: backend migrations (idempotent), a seed that first empties the
 * tables, and a signed admin cookie. The state dir is not deleted: the dev server (started
 * before this) already has the database open.
 */
export default function globalSetup() {
  wrangler("migrations", "apply", "DB");
  mkdirSync("e2e/.auth", { recursive: true });
  writeFileSync("e2e/.auth/seed.sql", seedSql(Date.now()));
  wrangler("execute", "DB", "--file", "e2e/.auth/seed.sql");

  const secret = readFileSync(".dev.vars.e2e", "utf8").match(/^BETTER_AUTH_SECRET=(.+)$/m)![1]!.trim();
  const signature = createHmac("sha256", secret).update(ADMIN_TOKEN).digest("base64");
  // http base URL → Better Auth uses the plain cookie name (no __Secure- prefix).
  writeFileSync(
    "e2e/.auth/admin.json",
    JSON.stringify({
      cookies: [{ name: "better-auth.session_token", value: encodeURIComponent(`${ADMIN_TOKEN}.${signature}`), domain: "localhost", path: "/", expires: -1, httpOnly: true, secure: false, sameSite: "Lax" }],
      origins: [],
    }),
  );
}
