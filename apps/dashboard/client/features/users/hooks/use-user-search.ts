import { zodResolver } from "@hookform/resolvers/zod";
import { useEffect } from "react";
import { useForm } from "react-hook-form";
import { useSearchParams } from "react-router";
import { useDebounce } from "../../../hooks/use-debounce";
import { type UserSearch, userSearchSchema } from "../schemas/user-search-schema";

/**
 * Search box: RHF holds the typed value (validated by zod), `q` is the debounced valid value
 * kept in the URL (?q=), so a search survives reload/back and fires one request per pause.
 */
export function useUserSearch() {
  const [params, setParams] = useSearchParams();
  const q = params.get("q") ?? "";
  const form = useForm<UserSearch>({ resolver: zodResolver(userSearchSchema), defaultValues: { q }, mode: "onChange" });
  const typed = form.watch("q");
  const debounced = useDebounce(typed.trim(), 300);
  const invalid = form.formState.errors.q !== undefined;

  // The header search navigates here with a new ?q=: mirror it into the field.
  useEffect(() => {
    if (q !== form.getValues("q").trim()) form.setValue("q", q);
  }, [q, form]);

  useEffect(() => {
    // Only a settled value goes to the URL: right after "clear" the debounced value is still the
    // old text, and writing it back would refill the field.
    if (invalid || debounced !== typed.trim() || debounced === q) return;
    setParams(debounced ? { q: debounced } : {}, { replace: true });
  }, [debounced, typed, invalid, q, setParams]);

  const clear = () => {
    form.setValue("q", "");
    setParams({}, { replace: true });
  };
  return { form, q, clear, error: form.formState.errors.q?.message };
}
