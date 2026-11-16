import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useNavigate } from "react-router";
import { signOut } from "../api/auth-api";

export function useSignOut() {
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  return useMutation({
    mutationFn: signOut,
    onSuccess: () => {
      queryClient.clear();
      void navigate("/login", { replace: true });
    },
  });
}
