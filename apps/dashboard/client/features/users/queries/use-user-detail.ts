import { queryOptions, useQuery } from "@tanstack/react-query";
import { getUser } from "../api/users-api";
import { usersKeys } from "./query-keys";

export const userDetailQuery = (id: string) =>
  queryOptions({ queryKey: usersKeys.detail(id), queryFn: () => getUser(id) });

export const useUserDetail = (id: string) => useQuery(userDetailQuery(id));
