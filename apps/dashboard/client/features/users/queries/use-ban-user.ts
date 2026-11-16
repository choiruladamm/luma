import { useMutation, useQueryClient } from "@tanstack/react-query";
import { banUser, unbanUser } from "../api/users-api";
import { usersKeys } from "./query-keys";

// After ban/unban the detail and every list page change; the overview's banned count catches
// up when its own cache goes stale (features don't reach into each other's keys).
function useUserMutation(mutationFn: (id: string) => Promise<unknown>) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn,
    onSuccess: (_data, id) =>
      Promise.all([
        queryClient.invalidateQueries({ queryKey: usersKeys.detail(id) }),
        queryClient.invalidateQueries({ queryKey: usersKeys.lists() }),
      ]),
  });
}

export const useBanUser = () => useUserMutation(banUser);
export const useUnbanUser = () => useUserMutation(unbanUser);
