import { api } from "../../../lib/api-client";
import { unwrap } from "../../../lib/api-error";

/** `query`: the non-default list params (usersSearchEntries), as strings. */
export const listUsers = (query: Record<string, string>) => unwrap(api.users.$get({ query }));

export const getUser = (id: string) => unwrap(api.users[":id"].$get({ param: { id } }));

/** The last 30 days of the app's usage rollup (the worker's default range). */
export const getUserUsage = (id: string) =>
  unwrap(api.users[":id"].usage.$get({ param: { id }, query: {} }));

export const banUser = (id: string) => unwrap(api.users[":id"].ban.$post({ param: { id } }));

export const unbanUser = (id: string) => unwrap(api.users[":id"].unban.$post({ param: { id } }));

export type UsersPage = Awaited<ReturnType<typeof listUsers>>;
export type UserListItem = UsersPage["items"][number];
export type UserDetail = Awaited<ReturnType<typeof getUser>>;
export type UserUsage = Awaited<ReturnType<typeof getUserUsage>>;
