export const invitesKeys = {
  all: ["invites"] as const,
  list: (entries: Record<string, string>) => [...invitesKeys.all, "list", entries] as const,
};
