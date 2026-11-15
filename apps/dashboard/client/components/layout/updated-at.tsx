import { formatDateTime } from "../../lib/format";
import { IconButton } from "../ui/button";

/** "Data per …" + manual refresh (no polling: the dashboard shares the free-tier quota). */
export function UpdatedAt({ at, onRefresh, refreshing }: { at: number; onRefresh: () => void; refreshing?: boolean }) {
  return (
    <div className="flex items-center gap-2">
      {at > 0 && <span className="text-caption text-ink2">Data per {formatDateTime(new Date(at).toISOString())}</span>}
      <IconButton icon="refresh" label="Muat ulang data" variant="sheet" onClick={onRefresh} disabled={refreshing} className={refreshing ? "[&_svg]:animate-spin" : undefined} />
    </div>
  );
}
