import { useMutation } from "@tanstack/react-query";
import { signInWithGoogle } from "../api/auth-api";

export const useSignIn = () => useMutation({ mutationFn: signInWithGoogle });
