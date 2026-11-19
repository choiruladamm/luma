import { zodResolver } from "@hookform/resolvers/zod";
import { useCallback, useEffect } from "react";
import { useForm, useWatch } from "react-hook-form";
import { useSearchParams } from "react-router";
import { useDebounce } from "../../../hooks/use-debounce";
import { useSearchWriter } from "../../../hooks/use-search-writer";
import { type UserSearch, userSearchSchema } from "../schemas/user-search-schema";

/**
 * Search box: RHF holds the typed value (validated by zod), `q` is the debounced valid value
 * kept in the URL (?q=), so a search survives reload/back and fires one request per pause.
 */
export function useUserSearch() {
  const [params] = useSearchParams();
  const write = useSearchWriter();
  const q = params.get("q") ?? "";
  const form = useForm<UserSearch>({
    resolver: zodResolver(userSearchSchema),
    defaultValues: { q },
    mode: "onChange",
  });
  const typed = useWatch({ control: form.control, name: "q" });
  const debounced = useDebounce(typed.trim(), 300);
  const invalid = form.formState.errors.q !== undefined;

  // The header search navigates here with a new ?q=: mirror it into the field.
  useEffect(() => {
    if (q !== form.getValues("q").trim()) form.setValue("q", q);
  }, [q, form]);

  // A new search keeps the filters and sort but goes back to page 1.
  const writeQ = useCallback(
    (value: string) =>
      write(
        (prev) => {
          if (value) prev.set("q", value);
          else prev.delete("q");
          prev.delete("page");
          return prev;
        },
        { replace: true },
      ),
    [write],
  );

  useEffect(() => {
    // Only a settled value goes to the URL: right after "clear" the debounced value is still the
    // old text, and writing it back would refill the field.
    if (invalid || debounced !== typed.trim() || debounced === q) return;
    writeQ(debounced);
  }, [debounced, typed, invalid, q, writeQ]);

  const clear = () => {
    form.setValue("q", "");
    writeQ("");
  };
  return { form, q, clear, invalid };
}
