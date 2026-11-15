import { useEffect } from "react";
import { Outlet, ScrollRestoration, useLocation } from "react-router";
import { AccountMenu } from "../components/layout/account-menu";
import { Wordmark } from "../components/layout/logo";
import { type NavItem, NavPanel, NavPills } from "../components/layout/nav";
import { IconButton } from "../components/ui/button";
import { Chip } from "../components/ui/chip";
import { ToastHost } from "../components/ui/toast-host";
import { useSession } from "../features/auth/queries/use-session";
import { useSignOut } from "../features/auth/queries/use-sign-out";
import { useOverview } from "../features/overview/queries/use-overview";
import { QuickSearch } from "../features/users/components/quick-search";
import { chooseLang, useI18n } from "../i18n";
import { isDevHost } from "../lib/env";
import { useUiStore } from "../stores/ui-store";

/**
 * Header for every admin screen (board 01–11): wordmark, nav pills, global email search, DEV
 * badge, account menu; on phones the nav becomes a burger panel. Only one menu open at a time.
 */
export function AppShell() {
  const session = useSession();
  const signOut = useSignOut();
  const overview = useOverview();
  const { theme, setTheme, openMenu, setOpenMenu } = useUiStore();
  const { t, lang } = useI18n();
  const location = useLocation();
  // The Users page has its own search field; two on one screen would compete.
  const searchable = location.pathname !== "/users";

  useEffect(() => setOpenMenu(null), [location.pathname, setOpenMenu]);

  const items: NavItem[] = [
    { to: "/", label: t.shell.overview, icon: "grid" },
    { to: "/users", label: t.shell.users, icon: "users", count: overview.data?.users.total },
    { to: "/invites", label: t.shell.invites, icon: "ticket", count: overview.data?.invites.unused },
  ];

  const user = session.data?.user;
  return (
    <div className="min-h-dvh bg-page">
      <div className="mx-auto flex max-w-[1280px] flex-col gap-7 px-4 pt-5 pb-12 md:px-8">
        <header className="flex min-h-[52px] items-center gap-2 md:flex-wrap md:gap-4">
          <Wordmark />
          <div className="hidden md:block">
            <NavPills items={items} />
          </div>
          <span className="flex-[1_1_24px]" />
          {searchable && (
            <div role="search" className="hidden min-w-[200px] flex-[0_1_320px] lg:block">
              <QuickSearch shortcut />
            </div>
          )}
          {searchable && (
            <IconButton
              icon={openMenu === "search" ? "x" : "search"}
              label={openMenu === "search" ? t.shell.closeSearch : t.shell.openSearch}
              variant="sheet"
              aria-expanded={openMenu === "search"}
              onClick={() => setOpenMenu(openMenu === "search" ? null : "search")}
              className="lg:hidden"
            />
          )}
          {isDevHost(window.location.hostname) && (
            <Chip tone="pink" icon="code" className="h-7 px-2.5 text-[11.5px] font-semibold tracking-[0.06em]">
              DEV
            </Chip>
          )}
          {user && (
            <AccountMenu
              user={user}
              open={openMenu === "account"}
              onToggle={() => setOpenMenu(openMenu === "account" ? null : "account")}
              onClose={() => setOpenMenu(null)}
              theme={theme}
              onTheme={setTheme}
              lang={lang}
              onLang={(l) => void chooseLang(l)}
              onSignOut={() => signOut.mutate()}
              signingOut={signOut.isPending}
            />
          )}
          <IconButton
            icon={openMenu === "nav" ? "x" : "menu"}
            label={openMenu === "nav" ? t.shell.closeNav : t.shell.openNav}
            variant="sheet"
            aria-expanded={openMenu === "nav"}
            aria-controls="menu-nav"
            onClick={() => setOpenMenu(openMenu === "nav" ? null : "nav")}
            className="md:hidden"
          />
        </header>
        {openMenu === "search" && searchable && (
          <div className="lg:hidden">
            <button type="button" tabIndex={-1} aria-label={t.shell.closeSearch} onClick={() => setOpenMenu(null)} className="fixed inset-0 top-[76px] z-10 cursor-default bg-scrim" />
            <div role="search" className="fixed inset-x-3.5 top-[76px] z-20 rounded-menu bg-sheet p-2 shadow-[var(--shadow-sheet),inset_0_0_0_1px_var(--c-track)]">
              <QuickSearch autoFocus tone="canvas" onDone={() => setOpenMenu(null)} />
            </div>
          </div>
        )}
        {openMenu === "nav" && (
          <div className="md:hidden">
            <button type="button" tabIndex={-1} aria-label={t.shell.closeNav} onClick={() => setOpenMenu(null)} className="fixed inset-0 top-[76px] z-10 cursor-default bg-scrim" />
            <NavPanel items={items} onNavigate={() => setOpenMenu(null)} />
          </div>
        )}
        <main className="flex flex-col gap-7">
          <Outlet />
        </main>
      </div>
      <ToastHost />
      {/* New screen → top of the page; back/forward → where the admin left it. */}
      <ScrollRestoration />
    </div>
  );
}
