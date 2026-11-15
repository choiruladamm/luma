import { useI18n } from "../../i18n";
import { formatDateTime } from "../../lib/format";
import { IconButton } from "../ui/button";

/** "Data per …" + manual refresh (no polling: the dashboard shares the free-tier quota). */
export function UpdatedAt({ at, onRefresh, refreshing }: { at: number; onRefresh: () => void; refreshing?: boolean }) {
  const { t, locale } = useI18n();
  return (
    <div className="flex items-center gap-2">
      {/* Fixed-width digits: a refresh changes the minute, and proportional digits would nudge the buttons. */}
      <span className="whitespace-nowrap text-caption tabular-nums text-ink2">{at > 0 ? t.common.dataAt(formatDateTime(new Date(at).toISOString(), locale)) : t.common.fetching}</span>
      <IconButton icon="refresh" label={t.common.refresh} variant="sheet" onClick={onRefresh} loading={refreshing} />
    </div>
  );
}
