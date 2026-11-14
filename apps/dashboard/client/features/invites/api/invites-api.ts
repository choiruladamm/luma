import { api } from "../../../lib/api-client";
import { unwrap } from "../../../lib/api-error";

export type InviteStatus = "unused" | "used";

export const listInvites = (status?: InviteStatus) => unwrap(api.invites.$get({ query: { status } }));

export const createInvites = (count: number) => unwrap(api.invites.$post({ json: { count } }));

/** 204 without a body. */
export async function deleteInvite(code: string) {
  await unwrap(api.invites[":code"].$delete({ param: { code } }).then((res) => ({ ok: res.ok, json: async () => null })));
}

export type InviteItem = Awaited<ReturnType<typeof listInvites>>["items"][number];
