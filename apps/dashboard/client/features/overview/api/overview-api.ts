import { api } from "../../../lib/api-client";
import { unwrap } from "../../../lib/api-error";

export const getOverview = () => unwrap(api.overview.$get());

export type Overview = Awaited<ReturnType<typeof getOverview>>;
