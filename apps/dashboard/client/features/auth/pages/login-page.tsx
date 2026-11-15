import { useMutation } from "@tanstack/react-query";
import { Navigate, useSearchParams } from "react-router";
import { LogoMark } from "../../../components/layout/logo";
import { Banner } from "../../../components/ui/banner";
import { Button } from "../../../components/ui/button";
import { Chip } from "../../../components/ui/chip";
import { type Messages, useI18n } from "../../../i18n";
import { errorText } from "../../../lib/api-error";
import { isDevHost } from "../../../lib/env";
import { signInWithGoogle } from "../api/auth-api";
import { useSession } from "../queries/use-session";

/** Copy for Better Auth's /login?error=…&error_description=… redirects (worker hooks). */
function loginError(params: URLSearchParams, t: Messages) {
  const code = params.get("error");
  if (!code) return null;
  const detail = params.get("error_description") ?? "";
  if (detail.includes("create accounts")) return { title: t.auth.notRegistered, body: t.auth.notRegisteredBody };
  if (code === "FORBIDDEN") return { title: t.auth.notAdmin, body: t.auth.notAdminBody };
  return { title: t.auth.failed, body: t.auth.failedBody };
}

// No board for Login: built from the foundation (sheet card, primary button, danger banner).
export function LoginPage() {
  const session = useSession();
  const [params] = useSearchParams();
  const signIn = useMutation({ mutationFn: signInWithGoogle });
  const { t } = useI18n();
  if (session.data) return <Navigate to="/" replace />;

  const error = loginError(params, t);
  return (
    <main className="flex min-h-dvh items-center justify-center bg-page px-4 py-12">
      <div className="flex w-full max-w-[420px] flex-col gap-6 rounded-dialog bg-sheet p-7 shadow-sheet">
        <div className="flex items-center justify-between">
          <span className="flex items-center gap-2">
            <LogoMark size={36} />
            <span className="font-display text-[22px] font-semibold tracking-[-0.02em]">Luma</span>
            <span className="text-card font-medium text-ink2">admin</span>
          </span>
          {isDevHost(window.location.hostname) && (
            <Chip tone="pink" icon="code">
              DEV
            </Chip>
          )}
        </div>
        <div className="flex flex-col gap-1.5">
          <h1 className="m-0 font-display text-title font-semibold">{t.auth.title}</h1>
          <p className="m-0 text-body text-ink2">{t.auth.hint}</p>
        </div>
        {error && <Banner title={error.title}>{error.body}</Banner>}
        {signIn.isError && <Banner title={t.auth.failed}>{errorText(signIn.error, t)}</Banner>}
        <Button variant="primary" size="lg" icon="google" onClick={() => signIn.mutate()} disabled={signIn.isPending || signIn.isSuccess}>
          {signIn.isPending || signIn.isSuccess ? t.auth.openingGoogle : t.auth.google}
        </Button>
        <p className="m-0 text-caption text-ink2">{t.auth.sessionNote}</p>
      </div>
    </main>
  );
}
