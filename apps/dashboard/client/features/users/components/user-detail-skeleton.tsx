import { Button } from "../../../components/ui/button";
import { Card, CardHeader } from "../../../components/ui/card";
import { Skeleton } from "../../../components/ui/skeleton";
import { useI18n } from "../../../i18n";

/**
 * Board 05 while loading (komponen 2, State): the profile, usage, AI, and device cards keep
 * their titles and labels; only the values are sand blocks. The ban section waits for the data
 * (it depends on whether the user is banned).
 */
export function UserDetailSkeleton() {
  const { t } = useI18n();
  const facts = [t.users.joined, t.users.lastActive, t.userDetail.signsInWith, t.userDetail.inviteCode];
  const numbers = [t.userDetail.bookFiles, t.users.syncData, t.userDetail.freeAi];
  return (
    <div aria-busy="true" aria-label={t.userDetail.loading} className="flex flex-col gap-7">
      <section className="flex flex-col gap-6 rounded-card bg-sheet p-6 md:p-7">
        <div className="flex flex-wrap items-center gap-5">
          <Skeleton className="size-[72px] flex-none" />
          <div className="flex min-w-0 flex-[1_1_320px] flex-col gap-2.5">
            <Skeleton className="h-7 w-64 max-w-full rounded-[10px]" />
            <div className="flex gap-2">
              <Skeleton className="h-4 w-24" />
              <Skeleton className="h-6 w-[68px]" />
            </div>
          </div>
          <Button variant="secondary" icon="copy" disabled>
            {t.userDetail.copyEmail}
          </Button>
        </div>
        <dl className="m-0 grid grid-cols-[repeat(auto-fit,minmax(180px,1fr))] gap-5 border-t border-track pt-5">
          {facts.map((label) => (
            <div key={label} className="flex flex-col gap-1.5">
              <dt className="text-caption font-medium text-ink2">{label}</dt>
              <dd className="m-0">
                <Skeleton className="h-4 w-32" />
              </dd>
            </div>
          ))}
        </dl>
      </section>
      <div className="flex flex-wrap gap-4">
        {numbers.map((title) => (
          <section key={title} className="flex flex-[1_1_260px] flex-col gap-3 rounded-card bg-sheet p-6">
            <h2 className="m-0 text-body font-semibold text-ink2">{title}</h2>
            <Skeleton className="h-[30px] w-28 rounded-[10px]" />
            <Skeleton className="h-3 w-40" />
          </section>
        ))}
      </div>
      <Card className="gap-3">
        <CardHeader title={t.userDetail.devices} subtitle={<Skeleton className="mt-1 h-3 w-56" />} />
        <ul className="m-0 flex list-none flex-col gap-2 p-0">
          {[0, 1].map((i) => (
            <li key={i} className="flex min-h-14 items-center gap-3 rounded-row bg-muted py-2 pr-4 pl-2">
              <span className="flex size-10 flex-none items-center justify-center rounded-tile-lg bg-sheet" />
              <span className="flex flex-1 flex-col gap-1.5">
                <Skeleton tone="track" className="h-3.5 w-32" />
                <Skeleton tone="track" className="h-3 w-44" />
              </span>
              <Skeleton tone="track" className="h-3 w-16" />
            </li>
          ))}
        </ul>
      </Card>
    </div>
  );
}
