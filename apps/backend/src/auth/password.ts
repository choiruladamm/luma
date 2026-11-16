// PBKDF2-SHA256 lewat crypto.subtle (native). Pengganti scrypt JS default Better Auth
// yang terlalu berat untuk CPU 10ms Workers free. Login email cuma ada di env dev.
import { b64, unb64 } from "../lib/encoding";

/** Iterasi dijaga supaya hash muat CPU 10ms di workerd (test/unit/password.test.ts). */
export const PBKDF2_ITERATIONS = 20_000;
const SALT_BYTES = 16;
const KEY_BITS = 256;


async function derive(password: string, salt: Uint8Array, iterations: number) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(password),
    "PBKDF2",
    false,
    ["deriveBits"],
  );
  const bits = await crypto.subtle.deriveBits(
    { name: "PBKDF2", hash: "SHA-256", salt, iterations },
    key,
    KEY_BITS,
  );
  return new Uint8Array(bits);
}

/** Format `pbkdf2$<iterasi>$<salt b64>$<hash b64>`: iterasi ikut disimpan supaya bisa dinaikkan nanti. */
export async function hashPassword(password: string, iterations = PBKDF2_ITERATIONS): Promise<string> {
  const salt = crypto.getRandomValues(new Uint8Array(SALT_BYTES));
  const hash = await derive(password, salt, iterations);
  return ["pbkdf2", iterations, b64(salt), b64(hash)].join("$");
}

export async function verifyPassword({ hash, password }: { hash: string; password: string }) {
  const [scheme, iter, salt, expected] = hash.split("$");
  const iterations = Number(iter);
  if (scheme !== "pbkdf2" || !salt || !expected || !Number.isInteger(iterations) || iterations < 1) {
    return false;
  }
  const actual = await derive(password, unb64(salt), iterations);
  const wanted = unb64(expected);
  return actual.length === wanted.length && crypto.subtle.timingSafeEqual(actual, wanted);
}
