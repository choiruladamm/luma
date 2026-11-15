import { isRouteErrorResponse, useRouteError } from "react-router";
import { LogoMark } from "../components/layout/logo";
import { Button, ButtonLink } from "../components/ui/button";
import { Icon, type IconName } from "../components/ui/icons";
import { useI18n } from "../i18n";

type Kind = "notFound" | "update" | "crash";

/** What went wrong, from the router's error: a 404, a stale chunk after a deploy, or a crash. */
function useErrorKind(): { kind: Kind; detail?: string } {
  const error = useRouteError();
  if (isRouteErrorResponse(error) && error.status === 404) return { kind: "notFound" };
  const message = error instanceof Error ? error.message : String(error ?? "");
  // A tab opened before a deploy asks for chunk files that no longer exist.
  if (/dynamically imported module|Importing a module script failed|error loading dynamically/i.test(message)) return { kind: "update" };
  return { kind: "crash", detail: error instanceof Error ? (error.stack ?? error.message) : message };
}

/** Komponen 2 State (failed load), scaled up: soft-red tile, title, one sentence, actions, details. */
function ErrorPanel({ kind, detail }: { kind: Kind; detail?: string }) {
  const { t } = useI18n();
  const icon: IconName = kind === "notFound" ? "search" : kind === "update" ? "refresh" : "alert";
  const copy = t.appError[kind];
  return (
    <div role={kind === "crash" ? "alert" : undefined} className="flex flex-col items-center gap-3 px-6 py-14 text-center">
      <span className={`flex size-14 items-center justify-center rounded-tile-lg ${kind === "crash" ? "bg-danger-soft text-danger-ink" : "bg-muted text-ink2"}`}>
        <Icon name={icon} size={24} />
      </span>
      <h1 className="m-0 font-display text-[22px] font-semibold">{copy.title}</h1>
      <p className="m-0 max-w-[440px] text-body text-ink2">{copy.body}</p>
      <div className="mt-2 flex flex-wrap justify-center gap-2.5">
        {kind !== "notFound" && (
          <Button variant="primary" icon="refresh" onClick={() => window.location.reload()}>
            {t.appError.reload}
          </Button>
        )}
        <ButtonLink to="/" variant="secondary" icon="grid" reloadDocument={kind !== "notFound"}>
          {t.appError.home}
        </ButtonLink>
      </div>
      {detail && (
        <details className="mt-4 w-full max-w-[560px] text-left">
          <summary className="cursor-pointer text-caption text-ink2">{t.appError.details}</summary>
          <pre className="mt-2 max-h-48 overflow-auto rounded-row bg-canvas p-3 font-mono text-[12px] whitespace-pre-wrap text-ink2 shadow-[inset_0_0_0_1px_var(--c-track)]">{detail}</pre>
        </details>
      )}
    </div>
  );
}

/** A screen failed: the card sits inside the shell, so the header and nav keep working. */
export function ScreenError() {
  const { kind, detail } = useErrorKind();
  return (
    <section className="rounded-card bg-sheet">
      <ErrorPanel kind={kind} detail={detail} />
    </section>
  );
}

/** Unknown URL inside the shell. */
export function NotFoundScreen() {
  return (
    <section className="rounded-card bg-sheet">
      <ErrorPanel kind="notFound" />
    </section>
  );
}

/** The shell or login failed: a centered card on the page, like the login screen. */
export function AppError() {
  const { kind, detail } = useErrorKind();
  return (
    <main className="flex min-h-dvh items-center justify-center bg-page px-4 py-12">
      <div className="flex w-full max-w-[560px] flex-col items-center rounded-dialog bg-sheet pt-7 shadow-sheet">
        <LogoMark size={32} />
        <ErrorPanel kind={kind} detail={detail} />
      </div>
    </main>
  );
}
