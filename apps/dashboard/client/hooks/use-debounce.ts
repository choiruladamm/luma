import { useEffect, useState } from "react";

/** `value`, but only after it stopped changing for `ms`. */
export function useDebounce<T>(value: T, ms = 300) {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const timer = setTimeout(() => setDebounced(value), ms);
    return () => clearTimeout(timer);
  }, [value, ms]);
  return debounced;
}
