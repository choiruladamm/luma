import { env } from "cloudflare:test";
import { eq } from "drizzle-orm";
import { describe, expect, it, vi } from "vitest";
import { createDb } from "../../src/db/client";
import { users } from "../../src/db/schema";
import { DELETE_PAGES_PER_REQUEST, deleteAccount } from "../../src/features/account/service";
import { signUp } from "../helpers/auth";

/** Bucket palsu yang selalu bilang masih ada halaman berikutnya. */
const endlessBucket = () => {
  const bucket = {
    list: vi.fn(async () => ({ objects: [{ key: "u/x/files/a" }], truncated: true })),
    delete: vi.fn(async () => {}),
  };
  return bucket;
};

describe("deleteAccount", () => {
  it("stops after the page budget and keeps the user until R2 is empty", async () => {
    const { userId } = await signUp();
    const bucket = endlessBucket();

    const result = await deleteAccount(createDb(env.DB), bucket as unknown as R2Bucket, userId);

    expect(result).toEqual({ status: "pending" });
    expect(bucket.list).toHaveBeenCalledTimes(DELETE_PAGES_PER_REQUEST);
    expect(bucket.delete).toHaveBeenCalledTimes(DELETE_PAGES_PER_REQUEST);
    const rows = await createDb(env.DB).select().from(users).where(eq(users.id, userId));
    expect(rows).toHaveLength(1);
  });

  it("deletes the user straight away when there is nothing in R2", async () => {
    const { userId } = await signUp();
    const result = await deleteAccount(createDb(env.DB), env.BUCKET, userId);
    expect(result).toEqual({ status: "deleted" });
  });
});
