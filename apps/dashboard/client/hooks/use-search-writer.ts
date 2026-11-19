import { useCallback, useLayoutEffect, useRef } from "react";
import { type NavigateOptions, useLocation, useNavigate } from "react-router";

type Update = (prev: URLSearchParams) => URLSearchParams | Record<string, string>;

/**
 * Stable writer for the URL search, safe in effect deps. React Router's `setSearchParams` changes
 * identity on every URL change and its updater sees the render's params, so two writes in one
 * tick drop the first; this one always starts from the latest search, including its own writes.
 */
export function useSearchWriter() {
  const { search } = useLocation();
  const navigate = useNavigate();
  const latest = useRef(search);
  useLayoutEffect(() => {
    latest.current = search;
  }, [search]);
  return useCallback(
    (update: Update, options?: NavigateOptions) => {
      const next = `?${new URLSearchParams(update(new URLSearchParams(latest.current)))}`;
      latest.current = next;
      void navigate(next, options);
    },
    [navigate],
  );
}
