import { useEffect, useState } from "react";
import { useSearchParams } from "react-router";
import { useDebounce } from "../../../hooks/use-debounce";

/**
 * Search box state: `input` follows typing, `q` is the debounced value kept in the URL (?q=),
 * so a search survives reload and back/forward and only fires one request per pause.
 */
export function useUserSearch() {
  const [params, setParams] = useSearchParams();
  const q = params.get("q") ?? "";
  const [input, setInput] = useState(q);
  const debounced = useDebounce(input.trim(), 300);

  useEffect(() => {
    if (debounced === q) return;
    setParams(debounced ? { q: debounced } : {}, { replace: true });
  }, [debounced, q, setParams]);

  return { input, setInput, q };
}
