import { useInfiniteQuery } from "@tanstack/react-query";
import { listUsers } from "../api/users-api";
import { usersKeys } from "./query-keys";

/** User list by email prefix; "Muat lagi" = fetchNextPage (server cursor, 50 per page). */
export const useUsers = (q: string) =>
  useInfiniteQuery({
    queryKey: usersKeys.list(q),
    queryFn: ({ pageParam }) => listUsers({ q: q || undefined, cursor: pageParam }),
    initialPageParam: undefined as string | undefined,
    getNextPageParam: (last) => last.nextCursor ?? undefined,
  });
