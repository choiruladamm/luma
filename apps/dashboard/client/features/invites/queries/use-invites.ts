import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createInvites, deleteInvite, type InviteStatus, listInvites } from "../api/invites-api";
import { invitesKeys } from "./query-keys";

export const useInvites = (status?: InviteStatus) =>
  useQuery({ queryKey: invitesKeys.list(status), queryFn: () => listInvites(status) });

function useInviteMutation<T>(mutationFn: (input: T) => Promise<unknown>) {
  const queryClient = useQueryClient();
  return useMutation({ mutationFn, onSuccess: () => queryClient.invalidateQueries({ queryKey: invitesKeys.all }) });
}

/** Returns `{codes}` to show and copy right after creating. */
export const useCreateInvites = () => useInviteMutation(createInvites);
export const useDeleteInvite = () => useInviteMutation(deleteInvite);
