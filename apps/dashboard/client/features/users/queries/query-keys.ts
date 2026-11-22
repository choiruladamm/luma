export const usersKeys = {
  all: ["users"] as const,
  lists: () => [...usersKeys.all, "list"] as const,
  // Keyed by the non-default params, so equal lists (header search, Users page 1) share an entry.
  list: (entries: Record<string, string>) => [...usersKeys.lists(), entries] as const,
  detail: (id: string) => [...usersKeys.all, "detail", id] as const,
  usage: (id: string) => [...usersKeys.all, "usage", id] as const,
};
