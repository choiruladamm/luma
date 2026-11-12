import { describe, expect, it } from "vitest";
import { hashPassword, PBKDF2_ITERATIONS, verifyPassword } from "../../src/auth/password";

describe("PBKDF2 password hashing", () => {
  it("verifies the right password and rejects a wrong one", async () => {
    const hash = await hashPassword("rahasia-banget-123");
    expect(hash.startsWith(`pbkdf2$${PBKDF2_ITERATIONS}$`)).toBe(true);
    expect(await verifyPassword({ hash, password: "rahasia-banget-123" })).toBe(true);
    expect(await verifyPassword({ hash, password: "rahasia-banget-124" })).toBe(false);
  });

  it("salts every hash", async () => {
    expect(await hashPassword("sama")).not.toBe(await hashPassword("sama"));
  });

  it("verifies hashes made with another iteration count (read from the hash)", async () => {
    const hash = await hashPassword("pw-lama-123", 1000);
    expect(hash.startsWith("pbkdf2$1000$")).toBe(true);
    expect(await verifyPassword({ hash, password: "pw-lama-123" })).toBe(true);
  });

  it.each(["", "bcrypt$x", "pbkdf2$abc$c2FsdA==$aGFzaA==", "pbkdf2$0$c2FsdA==$aGFzaA==", "pbkdf2$10$$"])(
    "rejects malformed hash %j",
    async (hash) => {
      expect(await verifyPassword({ hash, password: "apa-aja" })).toBe(false);
    },
  );
});
