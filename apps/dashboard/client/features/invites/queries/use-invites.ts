import { keepPreviousData, queryOptions, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { createInvites, deleteInvite, listInvites } from "../api/invites-api";
import { type InvitesParams, invitesSearchEntries } from "../hooks/use-invites-params";
import { invitesKeys } from "./query-keys";

/** One page of invites + the status counts (1 batch on the worker). */
export const invitesQuery = (params: InvitesParams) => {
  const entries = invitesSearchEntries(params);
  return queryOptions({ queryKey: invitesKeys.list(entries), queryFn: () => listInvites(entries) });
};

/** The previous page stays on screen while the next one loads, so paging doesn't flash a skeleton. */
export const useInvites = (params: InvitesParams) => useQuery({ ...invitesQuery(params), placeholderData: keepPreviousData });

function useInviteMutation<T, R>(mutationFn: (input: T) => Promise<R>) {
  const queryClient = useQueryClient();
  return useMutation({ mutationFn, onSuccess: () => queryClient.invalidateQueries({ queryKey: invitesKeys.all }) });
}

/** Returns `{codes}` to show and copy right after creating. */
export const useCreateInvites = () => useInviteMutation(createInvites);
export const useDeleteInvite = () => useInviteMutation(deleteInvite);
