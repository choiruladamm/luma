import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import type { ZodType } from "zod";
// Test-only: the kit's case helpers define how a /v1 shape maps to /v2.
import { toSnake } from "@luma/worker-kit/case";
import { backendWireErrorCode, errorBodySchema } from "../src/errors";
import { deleteResponse, meResponse } from "../src/backend/account";
import { configResponse, keyRequest, keyResponse, usageResponse } from "../src/backend/ai";
import {
  signInRequest,
  signInResponse,
  signUpRequest,
  signUpResponse,
  socialSignInRequest,
} from "../src/backend/auth";
import { backupInfo, backupsListResponse } from "../src/backend/backups";
import { missingRequest, missingResponse, putFileResponse } from "../src/backend/files";
import { healthResponse } from "../src/backend/health";
import { pullQuery, pullResponse, pushRequest, pushResponse } from "../src/backend/sync";
import { usageUploadRequest, usageUploadResponse } from "../src/backend/usage";

/** An error fixture: the shared body shape with a code the backend can emit. */
const error = "error";
const backendError = errorBodySchema.extend({
  error: errorBodySchema.shape.error.extend({ code: backendWireErrorCode }),
});

type Entry = { body?: ZodType; query?: ZodType; response: ZodType | typeof error };

/** Every fixture and the contract that parses it; a fixture missing here fails the test below. */
const contracts: Record<string, Entry> = {
  "ai-config": { response: configResponse },
  "ai-key-rotate": { body: keyRequest, response: keyResponse },
  "ai-key": { body: keyRequest, response: keyResponse },
  "ai-usage": { response: usageResponse },
  "auth-sign-in-email": { body: signInRequest, response: signInResponse },
  "auth-sign-in-social": { body: socialSignInRequest, response: signInResponse },
  "auth-sign-up-email": { body: signUpRequest, response: signUpResponse },
  "backups-list": { response: backupsListResponse },
  "backups-put": { response: backupInfo },
  "error-ai-banned-usage": { response: error },
  "error-ai-banned": { body: keyRequest, response: error },
  "error-backup-not-found": { response: error },
  "error-invalid-credentials": { body: signInRequest, response: error },
  "error-invalid-invite-code": { body: signUpRequest, response: error },
  "error-invite-code-required": { body: signUpRequest, response: error },
  "error-invite-code-used": { body: signUpRequest, response: error },
  "error-rate-limited": { response: error },
  "error-service-disabled": { response: error },
  "error-storage-full": { response: error },
  // The request is invalid on purpose: it is what the 400 answers.
  "error-sync-bad-request": { response: error },
  "error-sync-too-large": { response: error },
  "error-unauthorized": { response: error },
  "error-usage-future-day": { response: error },
  "files-missing": { body: missingRequest, response: missingResponse },
  "files-put": { response: putFileResponse },
  health: { response: healthResponse },
  "me-delete": { response: deleteResponse },
  me: { response: meResponse },
  "sync-pull-empty": { query: pullQuery, response: pullResponse },
  "sync-pull-newer-schema": { query: pullQuery, response: pullResponse },
  "sync-pull-tombstone": { query: pullQuery, response: pullResponse },
  "sync-pull": { query: pullQuery, response: pullResponse },
  "sync-push-older-schema": { body: pushRequest, response: pushResponse },
  "sync-push-tombstone": { body: pushRequest, response: pushResponse },
  "sync-push": { body: pushRequest, response: pushResponse },
  usage: { body: usageUploadRequest, response: usageUploadResponse },
};

const fixtures = (version: string) => join(import.meta.dirname, "../fixtures", version);
const dir = fixtures("v2");
const names = readdirSync(dir)
  .filter((f) => f.endsWith(".json"))
  .map((f) => f.slice(0, -".json".length));

/** Placeholders for dynamic values (fixtures README) get sample values that satisfy the schemas. */
const fill = (value: unknown): unknown => {
  if (value === "<token>" || value === "<id>") return "x";
  if (value === "<iso>") return "2026-01-01T00:00:00.000Z";
  if (Array.isArray(value)) return value.map(fill);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, fill(v)]));
  }
  return value;
};

type Fixture = {
  request: { path: string; body?: unknown };
  response: { status: number; body: unknown };
};

describe("v2 fixtures", () => {
  it("has a contract for every fixture file", () => {
    expect(names.toSorted()).toEqual(Object.keys(contracts).toSorted());
  });

  it.each(names)("%s parses with its contract", (name) => {
    const entry = contracts[name];
    if (!entry) throw new Error(`no contract for fixture ${name}`);
    const fixture = fill(JSON.parse(readFileSync(join(dir, `${name}.json`), "utf8"))) as Fixture;

    entry.body?.parse(fixture.request.body);
    entry.query?.parse(Object.fromEntries(new URL(fixture.request.path, "https://x").searchParams));
    const isError = entry.response === error;
    expect(fixture.response.status >= 400).toBe(isError);
    const schema = entry.response === error ? backendError : entry.response;
    schema.parse(fixture.response.body);
  });
});

/** What the `/v1` adapter leaves as is: sync's Drift JSON (docs/backend.md, Opaque payloads). */
const OPAQUE = ["request.body.records.*.data", "response.body.records.*.data"];

describe("v1 fixtures", () => {
  it("has a v1 fixture for every v2 fixture", () => {
    const v1 = readdirSync(fixtures("v1")).filter((f) => f.endsWith(".json"));
    expect(v1.toSorted()).toEqual(names.map((n) => `${n}.json`).toSorted());
  });

  // The adapter maps a v1 body to the v2 shape and back, so snake_case of a v1 fixture is its v2 fixture.
  it.each(names)("%s maps to its v2 fixture", (name) => {
    const read = (version: string) =>
      JSON.parse(readFileSync(join(fixtures(version), `${name}.json`), "utf8")) as Fixture;
    const v1 = read("v1");
    const v2 = read("v2");
    expect(v2.request.path).toBe(v1.request.path.replace("/v1/", "/v2/"));
    const mapped = toSnake(v1, OPAQUE) as Fixture;
    const expected = { ...mapped, request: { ...mapped.request, path: v2.request.path } };
    // The 400 message names the request's fields, so it names them as each version spells them.
    if (name === "error-sync-bad-request") {
      const body = expected.response.body as { error: { message: string } };
      body.error.message = body.error.message.replace("schemaVersion", "schema_version");
    }
    expect(expected).toEqual(v2);
  });
});

describe("backend wire error codes", () => {
  it("accept the backend's codes and any Better Auth code shape, nothing else", () => {
    expect(backendWireErrorCode.safeParse("STORAGE_FULL").success).toBe(true);
    expect(backendWireErrorCode.safeParse("PASSWORD_TOO_SHORT").success).toBe(true);
    expect(backendWireErrorCode.safeParse("password_too_short").success).toBe(false);
    expect(backendWireErrorCode.safeParse("").success).toBe(false);
  });
});
