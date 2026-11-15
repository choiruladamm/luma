import { type FormEvent, useEffect, useState } from "react";
import { Outlet, ScrollRestoration, useLocation, useNavigate } from "react-router";
import { AccountMenu } from "../components/layout/account-menu";
import { Wordmark } from "../components/layout/logo";
import { type NavItem, NavPanel, NavPills } from "../components/layout/nav";
import { IconButton } from "../components/ui/button";
import { Chip } from "../components/ui/chip";
import { SearchInput } from "../components/ui/search-input";
import { ToastHost } from "../components/ui/toast-host";
import { useSession } from "../features/auth/queries/use-session";
import { useSignOut } from "../features/auth/queries/use-sign-out";
import { useOverview } from "../features/overview/queries/use-overview";
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
  const navigate = useNavigate();
  const location = useLocation();
  const [search, setSearch] = useState("");

  useEffect(() => setOpenMenu(null), [location.pathname, setOpenMenu]);

  const items: NavItem[] = [
    { to: "/", label: "Ringkasan", icon: "grid" },
    { to: "/users", label: "User", icon: "users", count: overview.data?.users.total },
    { to: "/invites", label: "Undangan", icon: "ticket", count: overview.data?.invites.unused },
  ];

  const submitSearch = (e: FormEvent) => {
    e.preventDefault();
    const q = search.trim();
    void navigate(q ? `/users?q=${encodeURIComponent(q)}` : "/users");
    setSearch("");
  };

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
          <form role="search" onSubmit={submitSearch} className="hidden min-w-[200px] flex-[0_1_280px] lg:block">
            <SearchInput label="Cari email user" placeholder="Cari email user…" value={search} onChange={(e) => setSearch(e.target.value)} />
          </form>
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
              onSignOut={() => signOut.mutate()}
              signingOut={signOut.isPending}
            />
          )}
          <IconButton
            icon={openMenu === "nav" ? "x" : "menu"}
            label={openMenu === "nav" ? "Tutup navigasi" : "Buka navigasi"}
            variant="sheet"
            aria-expanded={openMenu === "nav"}
            aria-controls="menu-nav"
            onClick={() => setOpenMenu(openMenu === "nav" ? null : "nav")}
            className="md:hidden"
          />
        </header>
        {openMenu === "nav" && (
          <div className="md:hidden">
            <button type="button" tabIndex={-1} aria-label="Tutup navigasi" onClick={() => setOpenMenu(null)} className="fixed inset-0 top-[76px] z-10 cursor-default bg-scrim" />
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
