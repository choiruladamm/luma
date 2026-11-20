import { Card, CardHeader } from "../../../components/ui/card";
import { Chip } from "../../../components/ui/chip";
import { Icon, type IconName } from "../../../components/ui/icons";
import { Skeleton } from "../../../components/ui/skeleton";
import { useI18n } from "../../../i18n";

/** Backend kill switches, display only: they change via `vars` + deploy, not from here. */
export function ServicesCard({
  flags,
}: {
  flags?: { sync: boolean; backup: boolean; ai_key: boolean };
}) {
  const { t } = useI18n();
  const rows: [string, IconName, boolean | undefined][] = [
    ["Sync", "sync", flags?.sync],
    ["Backup", "cloud", flags?.backup],
    [t.overview.aiKey, "key", flags?.ai_key],
  ];
  return (
    <Card aria-labelledby="h-layanan" aria-busy={!flags || undefined} className="gap-3">
      <CardHeader
        id="h-layanan"
        title={t.overview.services}
        action={
          <span className="inline-flex items-center gap-1.5 text-caption text-ink2">
            <Icon name="lock" size={16} />
            {t.overview.statusOnly}
          </span>
        }
      />
      <ul className="m-0 flex list-none flex-col gap-2 p-0">
        {rows.map(([name, icon, on]) => (
          <li
            key={name}
            className="flex min-h-14 items-center gap-3 rounded-row bg-muted py-1.5 pr-2 pl-1.5"
          >
            <span className="flex size-11 flex-none items-center justify-center rounded-tile-lg bg-sheet">
              <Icon name={icon} size={20} />
            </span>
            <span className="flex-1 text-body font-semibold">{name}</span>
            {on === undefined ? (
              <Skeleton tone="track" className="h-6 w-[76px]" />
            ) : (
              <Chip tone={on ? "sheet" : "danger"} dot="filled">
                {on ? t.overview.on : t.overview.off}
              </Chip>
            )}
          </li>
        ))}
      </ul>
    </Card>
  );
}
