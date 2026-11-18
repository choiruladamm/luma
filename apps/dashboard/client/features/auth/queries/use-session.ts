import { queryOptions, useQuery } from "@tanstack/react-query";
import { getSession } from "../api/auth-api";
import { authKeys } from "./query-keys";

/** Admin session; fetched once per page load (5 min stale), the 12h cookie does the rest. */
// Coming back to the tab after an hour checks the session again: that's what slides it (once a day,
// server side) for a tab left open for days. Focus, not a timer: an unattended tab stays quiet and
// still times out after 7 idle days.
export const sessionQuery = queryOptions({
  queryKey: authKeys.session,
  queryFn: getSession,
  staleTime: 60 * 60_000,
  refetchOnWindowFocus: true,
});

export const useSession = () => useQuery(sessionQuery);
