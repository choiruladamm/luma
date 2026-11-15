import { queryOptions, useQuery } from "@tanstack/react-query";
import { getSession } from "../api/auth-api";
import { authKeys } from "./query-keys";

/** Admin session; fetched once per page load (5 min stale), the 12h cookie does the rest. */
export const sessionQuery = queryOptions({ queryKey: authKeys.session, queryFn: getSession, staleTime: 5 * 60_000 });

export const useSession = () => useQuery(sessionQuery);
