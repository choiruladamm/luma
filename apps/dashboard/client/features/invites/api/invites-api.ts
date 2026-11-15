import { api } from "../../../lib/api-client";
import { unwrap, unwrapEmpty } from "../../../lib/api-error";

export type InviteStatus = "unused" | "used";

export const listInvites = (status?: InviteStatus) => unwrap(api.invites.$get({ query: { status } }));

export const createInvites = (count: number) => unwrap(api.invites.$post({ json: { count } }));

/** 204 without a body. */
export const deleteInvite = (code: string) => unwrapEmpty(api.invites[":code"].$delete({ param: { code } }));

export type InviteItem = Awaited<ReturnType<typeof listInvites>>["items"][number];
