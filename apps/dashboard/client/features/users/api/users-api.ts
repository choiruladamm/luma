import { api } from "../../../lib/api-client";
import { unwrap } from "../../../lib/api-error";

export const listUsers = (query: { q?: string; cursor?: string }) => unwrap(api.users.$get({ query }));

export const getUser = (id: string) => unwrap(api.users[":id"].$get({ param: { id } }));

export const banUser = (id: string) => unwrap(api.users[":id"].ban.$post({ param: { id } }));

export const unbanUser = (id: string) => unwrap(api.users[":id"].unban.$post({ param: { id } }));

export type UsersPage = Awaited<ReturnType<typeof listUsers>>;
export type UserListItem = UsersPage["items"][number];
export type UserDetail = Awaited<ReturnType<typeof getUser>>;
