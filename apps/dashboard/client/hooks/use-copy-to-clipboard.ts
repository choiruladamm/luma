import { useCallback, useEffect, useState } from "react";

/** Copy text; `copied` holds the last copied value for `resetMs` (for a "Tersalin" state). */
export function useCopyToClipboard(resetMs = 2000) {
  const [copied, setCopied] = useState<string | null>(null);
  useEffect(() => {
    if (copied === null) return;
    const timer = setTimeout(() => setCopied(null), resetMs);
    return () => clearTimeout(timer);
  }, [copied, resetMs]);
  const copy = useCallback(async (text: string) => {
    await navigator.clipboard.writeText(text);
    setCopied(text);
  }, []);
  return { copied, copy };
}
