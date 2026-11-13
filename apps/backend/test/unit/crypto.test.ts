import { describe, expect, it } from "vitest";
import { decryptText, encryptText } from "../../src/lib/crypto";

const SECRET = btoa(String.fromCharCode(...new Uint8Array(32).fill(7)));
const OTHER = btoa(String.fromCharCode(...new Uint8Array(32).fill(9)));

describe("AES-GCM text sealing", () => {
  it("round-trips and uses a fresh IV every time", async () => {
    const a = await encryptText(SECRET, "sk-or-v1-rahasia");
    const b = await encryptText(SECRET, "sk-or-v1-rahasia");
    expect(a).not.toBe(b);
    expect(a.startsWith("v1.")).toBe(true);
    expect(await decryptText(SECRET, a)).toBe("sk-or-v1-rahasia");
  });

  it("returns null with the wrong key or tampered ciphertext", async () => {
    const sealed = await encryptText(SECRET, "sk-or-v1-rahasia");
    expect(await decryptText(OTHER, sealed)).toBeNull();
    const [v, iv, ct] = sealed.split(".");
    const flipped = `${ct!.slice(0, -2)}${ct!.endsWith("A=") ? "B=" : "A="}`;
    expect(await decryptText(SECRET, [v, iv, flipped].join("."))).toBeNull();
  });

  it.each(["", "v2.a.b", "v1..", "bukan-sealed"])("rejects malformed %j", async (sealed) => {
    expect(await decryptText(SECRET, sealed)).toBeNull();
  });
});
