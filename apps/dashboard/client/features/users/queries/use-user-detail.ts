import { useQuery } from "@tanstack/react-query";
import { getUser } from "../api/users-api";
import { usersKeys } from "./query-keys";

export const useUserDetail = (id: string) => useQuery({ queryKey: usersKeys.detail(id), queryFn: () => getUser(id) });
