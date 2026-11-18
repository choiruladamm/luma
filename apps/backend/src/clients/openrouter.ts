// Thin client for the OpenRouter management API (docs/backend.md, AI subsidy). One function =
// one subrequest. Mocked with MSW (@msw/cloudflare) in tests.

export const OPENROUTER_API = "https://openrouter.ai/api/v1";

export class OpenRouterError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

export type CreatedKey = { key: string; hash: string };
export type KeyUsage = { limit: number | null; limitRemaining: number | null; usageDaily: number };

export type OpenRouterAdmin = {
  createKey(input: {
    name: string;
    limitUsd: number;
    expiresAt: Date;
    workspaceId: string;
  }): Promise<CreatedKey>;
  updateLimit(hash: string, limitUsd: number): Promise<void>;
  getUsage(hash: string): Promise<KeyUsage>;
  /** False when the key no longer exists on OpenRouter (404). */
  keyExists(hash: string): Promise<boolean>;
  /** A 404 (already gone) counts as success. */
  deleteKey(hash: string): Promise<void>;
};

export function openRouterAdmin(
  managementKey: string,
  fetcher: typeof fetch = fetch,
): OpenRouterAdmin {
  const call = async (method: string, path: string, body?: unknown) => {
    const res = await fetcher(`${OPENROUTER_API}${path}`, {
      method,
      headers: {
        authorization: `Bearer ${managementKey}`,
        ...(body === undefined ? {} : { "content-type": "application/json" }),
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (!res.ok)
      throw new OpenRouterError(res.status, `OpenRouter ${method} ${path}: ${res.status}`);
    return (await res.json()) as Record<string, unknown>;
  };

  return {
    async createKey({ name, limitUsd, expiresAt, workspaceId }) {
      const res = await call("POST", "/keys", {
        name,
        limit: limitUsd,
        limit_reset: "daily",
        include_byok_in_limit: true,
        expires_at: expiresAt.toISOString(),
        workspace_id: workspaceId,
      });
      const data = res.data as { hash: string };
      return { key: res.key as string, hash: data.hash };
    },
    async updateLimit(hash, limitUsd) {
      await call("PATCH", `/keys/${hash}`, { limit: limitUsd });
    },
    async getUsage(hash) {
      const data = (await call("GET", `/keys/${hash}`)).data as {
        limit: number | null;
        limit_remaining: number | null;
        usage_daily: number;
      };
      return {
        limit: data.limit,
        limitRemaining: data.limit_remaining,
        usageDaily: data.usage_daily,
      };
    },
    async keyExists(hash) {
      try {
        await call("GET", `/keys/${hash}`);
        return true;
      } catch (e) {
        if (e instanceof OpenRouterError && e.status === 404) return false;
        throw e;
      }
    },
    async deleteKey(hash) {
      try {
        await call("DELETE", `/keys/${hash}`);
      } catch (e) {
        if (!(e instanceof OpenRouterError && e.status === 404)) throw e;
      }
    },
  };
}
