import { describe, expect, it } from "vitest";
import { camelKey, snakeJson, snakeKey, toCamel, toSnake } from "../src/case";

describe("keys", () => {
  it.each([
    ["createdAt", "created_at"],
    ["r2Bytes", "r2_bytes"],
    ["new7d", "new7d"],
    ["id", "id"],
    ["lastActiveAt", "last_active_at"],
  ])("%s <-> %s", (camel, snake) => {
    expect(snakeKey(camel)).toBe(snake);
    expect(camelKey(snake)).toBe(camel);
  });
  it("acronyms do not round-trip: callbackURL -> callback_url -> callbackUrl", () => {
    expect(snakeKey("callbackURL")).toBe("callback_url");
    expect(snakeKey("URLPath")).toBe("url_path");
    expect(camelKey("callback_url")).toBe("callbackUrl");
  });
});

describe("toSnake / toCamel", () => {
  const camel = {
    userId: "u",
    items: [{ createdAt: 1, usedBy: null }, 3, "x"],
    flags: { aiKey: true },
  };
  const snake = {
    user_id: "u",
    items: [{ created_at: 1, used_by: null }, 3, "x"],
    flags: { ai_key: true },
  };
  it("converts deeply and round-trips", () => {
    expect(toSnake(camel)).toEqual(snake);
    expect(toCamel(snake)).toEqual(camel);
    expect(toCamel(toSnake(camel))).toEqual(camel);
  });
  it("passes primitives through", () => {
    expect(toSnake(null)).toBeNull();
    expect(toSnake("aB")).toBe("aB");
  });
  it("skips values by path pattern, still converting the key", () => {
    const input = {
      syncData: { fooBar: 1 },
      records: [
        { rowId: 1, data: { innerKey: 2 } },
        { rowId: 2, data: { innerKey: 3 } },
      ],
    };
    expect(toSnake(input, ["records.*.data"])).toEqual({
      sync_data: { foo_bar: 1 },
      records: [
        { row_id: 1, data: { innerKey: 2 } },
        { row_id: 2, data: { innerKey: 3 } },
      ],
    });
    expect(toSnake({ aB: { cD: 1 } }, ["*.cD"])).toEqual({ a_b: { c_d: 1 } });
    expect(toSnake({ aB: { cD: 1 } }, ["aB"])).toEqual({ a_b: { cD: 1 } });
    expect(toSnake({ aB: { cD: 1 } }, ["aB.cD.eF"])).toEqual({ a_b: { c_d: 1 } });
  });
  it("skips by predicate and in toCamel", () => {
    expect(toSnake({ aB: { cD: 1 } }, (p) => p === "aB")).toEqual({ a_b: { cD: 1 } });
    expect(toCamel({ a_b: { c_d: 1 } }, ["a_b"])).toEqual({ aB: { c_d: 1 } });
  });
});

describe("snakeJson", () => {
  it("converts a JSON body, keeping status and headers", async () => {
    const res = await snakeJson(
      new Response(JSON.stringify({ expiresAt: "x" }), {
        status: 201,
        headers: { "content-type": "application/json", "content-length": "20", "x-a": "1" },
      }),
    );
    expect(res.status).toBe(201);
    expect(res.headers.get("x-a")).toBe("1");
    expect(res.headers.get("content-length")).toBeNull();
    expect(await res.json()).toEqual({ expires_at: "x" });
  });
  it("passes non-JSON and empty bodies through", async () => {
    const text = new Response("aB", { headers: { "content-type": "text/plain" } });
    expect(await snakeJson(text)).toBe(text);
    const empty = new Response(null, {
      status: 200,
      headers: { "content-type": "application/json" },
    });
    expect(await snakeJson(empty)).toBe(empty);
  });

  it("passes a malformed JSON body through instead of failing the request", async () => {
    const broken = new Response("{ nope", { headers: { "content-type": "application/json" } });
    expect(await snakeJson(broken)).toBe(broken);
  });
});

describe("leading underscores", () => {
  it("stay part of the name in both directions", () => {
    expect(camelKey("_id")).toBe("_id");
    expect(camelKey("__proto__")).toBe("__proto__");
    expect(camelKey("_user_id")).toBe("_userId");
    expect(snakeKey("_id")).toBe("_id");
  });
});
