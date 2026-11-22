import { api } from "../../../lib/api-client";
import { unwrap } from "../../../lib/api-error";

export const getOverview = () => unwrap(api.overview.$get());

/** The last 30 days of every user's usage rollup (the worker's default range). */
export const getUsageOverview = () => unwrap(api.overview.usage.$get({ query: {} }));

export type UsageOverview = Awaited<ReturnType<typeof getUsageOverview>>;
export type Overview = Awaited<ReturnType<typeof getOverview>>;
