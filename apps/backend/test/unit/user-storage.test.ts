import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { createDb } from "../../src/db/client";
import { releaseOnFailure, reserveBytes, storedBytes } from "../../src/db/user-storage";
import { signUp } from "../helpers/auth";

describe("reserveBytes", () => {
  it("allows filling the quota exactly, not past it", async () => {
    const { userId } = await signUp();
    const db = createDb(env.DB);

    await reserveBytes(db, userId, 90, 100);
    await reserveBytes(db, userId, 10, 100);
    await expect(reserveBytes(db, userId, 1, 100)).rejects.toThrow("Cloud storage is full");
    await expect(reserveBytes(createDb(env.DB), (await signUp()).userId, 101, 100)).rejects.toThrow(
      "Cloud storage is full",
    );
    expect(await storedBytes(db, userId)).toBe(100);
  });

  it("lets only what fits through when uploads race", async () => {
    const { userId } = await signUp();
    const db = createDb(env.DB);

    const results = await Promise.allSettled(Array.from({ length: 5 }, () => reserveBytes(db, userId, 30, 100)));

    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(3);
    expect(await storedBytes(db, userId)).toBe(90);
  });

  it("gives the reservation back when the upload fails", async () => {
    const { userId } = await signUp();
    const db = createDb(env.DB);
    await reserveBytes(db, userId, 40, 100);

    await expect(
      releaseOnFailure(db, userId, 40, async () => {
        throw new Error("R2 down");
      }),
    ).rejects.toThrow("R2 down");
    expect(await storedBytes(db, userId)).toBe(0);
  });
});
