import { Button, IconButton } from "../../../components/ui/button";
import { Card, CardHeader } from "../../../components/ui/card";
import { Skeleton } from "../../../components/ui/skeleton";
import { useI18n } from "../../../i18n";
import { NUMBER_GRID, NumberCard } from "./user-detail-cards";

/** A text-shaped block inside the real text element, so the line keeps its real height. */
const Line = ({ className }: { className: string }) => <Skeleton className={`inline-block align-middle ${className}`} />;

/**
 * Board 05 while loading (komponen 2, State): the same boxes as the loaded page (profile, the
 * three number cards, devices, ban section) with their titles and labels; only values pulse.
 * Text blocks sit inside the real text elements so nothing shifts when the data lands.
 */
export function UserDetailSkeleton() {
  const { t } = useI18n();
  const facts = [t.users.joined, t.users.lastActive, t.userDetail.signsInWith, t.userDetail.inviteCode];
  return (
    <div aria-busy="true" aria-label={t.userDetail.loading} className="contents">
      <section className="flex flex-col gap-5 rounded-card bg-sheet p-5 md:gap-6 md:p-7">
        <div className="flex items-start gap-3.5 md:flex-wrap md:items-center md:gap-5">
          <Skeleton className="size-14 flex-none md:size-[72px]" />
          <div className="flex min-w-0 flex-1 flex-col gap-1.5 md:flex-[1_1_320px]">
            <h1 className="m-0 font-display text-[22px] leading-[1.2] font-semibold md:text-title">
              <Line className="h-[0.8em] w-[min(320px,100%)] rounded-[10px]" />
            </h1>
            <div className="flex flex-wrap items-center gap-2">
              <span className="text-body text-ink2">
                <Line className="h-3 w-16" />
              </span>
              <Skeleton className="h-6 w-[68px]" />
            </div>
          </div>
          <Button variant="secondary" icon="copy" disabled className="max-md:hidden">
            {t.userDetail.copyEmail}
          </Button>
          <IconButton icon="copy" label={t.userDetail.copyEmail} disabled className="flex-none md:hidden" />
        </div>
        <dl className="m-0 grid grid-cols-2 gap-x-4 gap-y-4 border-t border-track pt-5 md:grid-cols-[repeat(auto-fit,minmax(180px,1fr))] md:gap-5">
          {facts.map((label) => (
            <div key={label} className="flex flex-col gap-1">
              <dt className="text-caption font-medium text-ink2">{label}</dt>
              <dd className="m-0 text-body font-semibold">
                <Line className="h-3.5 w-32" />
              </dd>
            </div>
          ))}
        </dl>
      </section>
      <div className={NUMBER_GRID}>
        <NumberCard title={t.userDetail.bookFiles} value={<Line className="h-[20px] w-20 rounded-[8px] md:h-[26px]" />}>
          <div className="h-2 rounded-full bg-track" />
          <span className="text-caption">
            <Line className="h-3 w-44" />
          </span>
        </NumberCard>
        <NumberCard title={t.users.syncData} value={<Line className="h-[20px] w-20 rounded-[8px] md:h-[26px]" />}>
          <span className="text-caption text-ink2">{t.userDetail.syncNote}</span>
        </NumberCard>
        <NumberCard wide title={t.userDetail.freeAi} value={<Line className="h-[20px] w-28 rounded-[8px] md:h-[26px]" />}>
          <span className="flex flex-col text-caption">
            <span>
              <Line className="h-3 w-full max-w-[280px]" />
            </span>
            <span>
              <Line className="h-3 w-40" />
            </span>
          </span>
        </NumberCard>
      </div>
      <Card className="gap-3">
        <CardHeader title={t.userDetail.devices} subtitle={<Line className="h-3 w-48" />} />
        <ul className="m-0 flex list-none flex-col gap-2 p-0">
          <li className="flex min-h-14 items-center gap-3 rounded-row bg-muted py-2 pr-4 pl-2">
            <span className="flex size-10 flex-none items-center justify-center rounded-tile-lg bg-sheet" />
            <span className="flex min-w-0 flex-1 flex-col gap-0.5">
              <span className="text-body font-semibold">
                <Skeleton tone="track" className="inline-block h-3.5 w-24 align-middle" />
              </span>
              <span className="text-caption">
                <Skeleton tone="track" className="inline-block h-3 w-40 align-middle" />
              </span>
            </span>
            <Skeleton tone="track" className="h-3 w-16" />
          </li>
        </ul>
      </Card>
      {/* Most users aren't banned, so the ban section's box is held too (banned users get the banner instead). */}
      <section className="flex flex-wrap items-center justify-between gap-4 rounded-card bg-sheet p-6">
        <div className="flex max-w-[640px] flex-1 flex-col gap-1">
          <h2 className="m-0 text-card font-semibold">{t.userDetail.banTitle}</h2>
          <span className="flex flex-col text-body">
            <span>
              <Line className="h-3.5 w-full max-w-[560px]" />
            </span>
            <span>
              <Line className="h-3.5 w-72" />
            </span>
          </span>
        </div>
        <Skeleton className="h-11 w-[124px]" />
      </section>
    </div>
  );
}
