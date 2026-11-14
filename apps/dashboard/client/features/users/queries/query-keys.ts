export const usersKeys = {
  all: ["users"] as const,
  lists: () => [...usersKeys.all, "list"] as const,
  list: (q: string) => [...usersKeys.lists(), q] as const,
  detail: (id: string) => [...usersKeys.all, "detail", id] as const,
};
