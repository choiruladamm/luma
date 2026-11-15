import { Card, CardHeader } from "../../../components/ui/card";
import { Icon } from "../../../components/ui/icons";
import { ProgressBar } from "../../../components/ui/meter";
import { formatBytes, formatDate, formatRelative, formatUsd } from "../../../lib/format";
import type { UserDetail } from "../api/users-api";

function NumberCard({ title, value, children }: { title: string; value: string; children?: React.ReactNode }) {
  return (
    <section className="flex flex-[1_1_260px] flex-col gap-3 rounded-card bg-sheet p-6">
      <h2 className="m-0 text-body font-semibold text-ink2">{title}</h2>
      <span className="text-[30px] leading-none font-semibold tracking-[-0.03em] tabular-nums">{value}</span>
      {children}
    </section>
  );
}

/** File and sync usage; the share of all files shows only when the overview is already cached. */
export function UsageCards({ user, totalR2 }: { user: UserDetail; totalR2?: number }) {
  const share = totalR2 ? (user.r2Bytes / totalR2) * 100 : undefined;
  return (
    <>
      <NumberCard title="File buku" value={formatBytes(user.r2Bytes)}>
        {share !== undefined && (
          <>
            <ProgressBar value={share} label="Bagian dari semua file di server" />
            <span className="text-caption text-ink2">{share < 1 && user.r2Bytes > 0 ? "<1" : Math.round(share)}% dari semua file di server</span>
          </>
        )}
      </NumberCard>
      <NumberCard title="Data sync" value={formatBytes(user.syncBytes)}>
        <span className="text-caption text-ink2">progres, catatan & pengaturan AI</span>
      </NumberCard>
    </>
  );
}

/** Subsidized key only (an own key never reaches the server): today's use vs the daily limit. */
export function AiCard({ ai }: { ai: UserDetail["ai"] }) {
  return (
    <NumberCard title="Kuota AI gratis" value={ai ? (ai.usageDaily === null ? "—" : formatUsd(ai.usageDaily)) : "Gak pakai"}>
      {ai ? (
        <>
          {ai.usageDaily !== null && <ProgressBar value={(ai.usageDaily / ai.limit) * 100} label="Pemakaian AI hari ini" />}
          <span className="text-caption text-ink2">
            {ai.usageDaily === null ? "Pemakaian gagal dimuat dari OpenRouter. " : `hari ini dari ${formatUsd(ai.limit)} · `}
            key berlaku sampai {formatDate(ai.expiresAt)}
          </span>
        </>
      ) : (
        <span className="text-caption text-ink2">Belum minta key subsidi, atau pakai key sendiri. Key-nya gak pernah ditampilin di sini.</span>
      )}
    </NumberCard>
  );
}

/** "Luma/0.3.0 (+mailto:…)" → "App Luma 0.3.0"; browsers and tools keep a short raw label. */
export function deviceLabel(userAgent: string | null) {
  if (!userAgent) return "Perangkat gak dikenal";
  const app = userAgent.match(/^Luma\/([\w.]+)/);
  if (app) return `App Luma ${app[1]}`;
  if (userAgent.includes("Mozilla")) return "Browser";
  return userAgent.split(" ")[0]!;
}

/** Sessions per device (in scope, not on the board): newest first, max 50 from the API. */
export function SessionsCard({ sessions }: { sessions: UserDetail["sessions"] }) {
  return (
    <Card aria-labelledby="h-sesi" className="gap-3">
      <CardHeader id="h-sesi" title="Perangkat" subtitle={`${sessions.length} sesi masuk, termasuk yang udah kedaluwarsa`} />
      {sessions.length === 0 ? (
        <span className="text-body text-ink2">Belum ada sesi.</span>
      ) : (
        <ul className="m-0 flex list-none flex-col gap-2 p-0">
          {sessions.map((s, i) => (
            <li key={i} className="flex min-h-14 items-center gap-3 rounded-row bg-muted py-2 pr-4 pl-2">
              <span className="flex size-10 flex-none items-center justify-center rounded-tile-lg bg-sheet">
                <Icon name={s.userAgent?.startsWith("Luma/") ? "phone" : "monitor"} size={20} />
              </span>
              <span className="flex min-w-0 flex-1 flex-col gap-0.5">
                <span className="truncate text-body font-semibold" title={s.userAgent ?? undefined}>
                  {deviceLabel(s.userAgent)}
                </span>
                <span className="truncate text-caption text-ink2">
                  Masuk {formatDate(s.createdAt)}
                  {s.ipAddress ? ` · ${s.ipAddress}` : ""}
                </span>
              </span>
              <span className="text-caption whitespace-nowrap text-ink2">{formatRelative(s.updatedAt)}</span>
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}
