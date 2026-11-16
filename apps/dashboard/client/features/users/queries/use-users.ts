import { keepPreviousData, queryOptions, useQuery } from "@tanstack/react-query";
import { listUsers } from "../api/users-api";
import { type UsersParams, usersSearchEntries } from "../hooks/use-users-params";
import { usersKeys } from "./query-keys";

/** One page of users for the given filters, sort, and page (1 batch on the worker: rows + total). */
export const usersQuery = (params: UsersParams) => {
  const entries = usersSearchEntries(params);
  return queryOptions({ queryKey: usersKeys.list(entries), queryFn: () => listUsers(entries) });
};

/**
 * `enabled: false` for a query not worth sending yet (the header search below 2 characters). The
 * previous page stays on screen while the next one loads, so paging doesn't flash a skeleton.
 */
export const useUsers = (params: UsersParams, enabled = true) => useQuery({ ...usersQuery(params), enabled, placeholderData: keepPreviousData });
