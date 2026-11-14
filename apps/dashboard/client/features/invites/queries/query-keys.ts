import type { InviteStatus } from "../api/invites-api";

export const invitesKeys = {
  all: ["invites"] as const,
  list: (status?: InviteStatus) => [...invitesKeys.all, status ?? "all"] as const,
};
