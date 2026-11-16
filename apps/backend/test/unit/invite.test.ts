import { describe, expect, it } from "vitest";
import { newInviteCode, normalizeInviteCode } from "../../src/auth/invite";

describe("normalizeInviteCode", () => {
  it.each([
    ["LUMA-7Q2K", "LUMA-7Q2K"],
    ["luma-7q2k", "LUMA-7Q2K"],
    ["luma7q2k", "LUMA-7Q2K"],
    ["  Luma 7Q2K ", "LUMA-7Q2K"],
    ["TEST-1-ABC", "TEST1ABC"],
    ["LUMA", "LUMA"],
  ])("%j → %j", (input, expected) => {
    expect(normalizeInviteCode(input)).toBe(expected);
  });
});

describe("newInviteCode", () => {
  it("makes long random codes that survive normalization", () => {
    const codes = Array.from({ length: 50 }, newInviteCode);
    for (const code of codes) {
      expect(code).toMatch(/^LUMA-[2-9A-HJ-NP-Z]{5}-[2-9A-HJ-NP-Z]{5}$/);
      expect(normalizeInviteCode(code)).toBe(normalizeInviteCode(code.toLowerCase().replaceAll("-", "")));
    }
    expect(new Set(codes).size).toBe(50);
  });
});
