export const overviewKeys = {
  all: ["overview"] as const,
  usage: () => [...overviewKeys.all, "usage"] as const,
};
