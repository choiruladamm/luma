import { env } from "cloudflare:test";
import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import {
  bearerToken,
  findSessionUser,
  SESSION_EXPIRES_IN_MS,
  SESSION_UPDATE_AGE_MS,
} from "../../src/auth/session";
import { createDb } from "../../src/db/client";
import { sessions } from "../../src/db/schema";
import { signUp } from "../helpers/auth";
import { countingD1 } from "../helpers/budget";

const tokenOf = (signed: string) => signed.split(".")[0] ?? "";

describe("bearerToken", () => {
  it.each([
    ["Bearer abc.sig", "abc"],
    ["bearer abc", "abc"],
    ["Bearer   abc", "abc"],
    [undefined, null],
    ["", null],
    ["Basic abc", null],
    ["Bearer", null],
    ["Bearer .sig", null],
  ])("%j → %j", (header, expected) => {
    expect(bearerToken(header)).toBe(expected);
  });
});

describe("findSessionUser", () => {
  it("returns the user for a valid token with a single D1 query", async () => {
    const { token, userId } = await signUp();
    const d1 = countingD1(env.DB);
    const user = await findSessionUser(createDb(d1.db), `Bearer ${token}`);
    expect(user?.id).toBe(userId);
    expect(d1.count()).toBe(1);
  });

  it("rejects unknown and expired sessions", async () => {
    const { token } = await signUp();
    const db = createDb(env.DB);
    expect(await findSessionUser(db, "Bearer tidak-ada")).toBeNull();
    const later = new Date(Date.now() + SESSION_EXPIRES_IN_MS + 1000);
    expect(await findSessionUser(db, `Bearer ${token}`, later)).toBeNull();
  });

  it("extends the session at most once per day", async () => {
    const { token } = await signUp();
    const db = createDb(env.DB);
    const read = async () =>
      (await db.select().from(sessions).where(eq(sessions.token, tokenOf(token))))[0]!.expiresAt.getTime();
    const before = await read();

    const sameDay = countingD1(env.DB);
    await findSessionUser(createDb(sameDay.db), `Bearer ${token}`, new Date(Date.now() + 1000));
    expect(sameDay.count()).toBe(1);
    expect(await read()).toBe(before);

    const twoDaysLater = new Date(Date.now() + 2 * SESSION_UPDATE_AGE_MS);
    const nextDay = countingD1(env.DB);
    await findSessionUser(createDb(nextDay.db), `Bearer ${token}`, twoDaysLater);
    expect(nextDay.count()).toBe(2);
    expect(await read()).toBe(twoDaysLater.getTime() + SESSION_EXPIRES_IN_MS);
  });
});
