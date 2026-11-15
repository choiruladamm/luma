import { infiniteQueryOptions, useInfiniteQuery } from "@tanstack/react-query";
import { listUsers } from "../api/users-api";
import { usersKeys } from "./query-keys";

/** User list by email prefix; "Muat lagi" = fetchNextPage (server cursor, 50 per page). */
export const usersQuery = (q: string) =>
  infiniteQueryOptions({
    queryKey: usersKeys.list(q),
    queryFn: ({ pageParam }) => listUsers({ q: q || undefined, cursor: pageParam }),
    initialPageParam: undefined as string | undefined,
    getNextPageParam: (last) => last.nextCursor ?? undefined,
  });

/** `enabled: false` for a query not worth sending yet (the header search below 2 characters). */
export const useUsers = (q: string, enabled = true) => useInfiniteQuery({ ...usersQuery(q), enabled });
