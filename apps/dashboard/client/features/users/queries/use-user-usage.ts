import { queryOptions, useQuery } from "@tanstack/react-query";
import { getUserUsage } from "../api/users-api";
import { usersKeys } from "./query-keys";

export const userUsageQuery = (id: string) =>
  queryOptions({ queryKey: usersKeys.usage(id), queryFn: () => getUserUsage(id) });

export const useUserUsage = (id: string) => useQuery(userUsageQuery(id));
