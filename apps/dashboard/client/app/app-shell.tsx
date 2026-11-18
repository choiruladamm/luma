import { type CSSProperties, useEffect, useLayoutEffect, useRef, useState } from "react";
import { Outlet, ScrollRestoration, useLocation } from "react-router";
import { AccountMenu } from "../components/layout/account-menu";
import { LogoMark, Wordmark } from "../components/layout/logo";
import { type NavItem, NavPills, NavTabBar } from "../components/layout/nav";
import { IconButton } from "../components/ui/button";
import { Chip } from "../components/ui/chip";
import { ToastHost } from "../components/ui/toast-host";
import { useSession } from "../features/auth/queries/use-session";
import { useSignOut } from "../features/auth/queries/use-sign-out";
import { useOverview } from "../features/overview/queries/use-overview";
import { QuickSearch } from "../features/users/components/quick-search";
import { chooseLang, useI18n } from "../i18n";
import { cn } from "../lib/cn";
import { isDevHost } from "../lib/env";
import { useUiStore } from "../stores/ui-store";

// Every full page load (the Google sign-in redirect, a typed URL) starts with location.key
// "default", so a position saved on an earlier visit in this tab would be restored there. A key
// per load makes a fresh load start at the top; in-app back/forward still restores.
const PAGE_LOAD = Date.now();
const scrollKey = (location: { key: string }) =>
  location.key === "default" ? `load-${PAGE_LOAD}` : location.key;

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

  // Phone menus and scrims start under the real header (its height varies with wrapping),
  // instead of a guessed offset that overlapped it.
  const searching = openMenu === "search" && searchable;

  // Once the header has scrolled out of view, a separate compact nav floats in from the top
  // (desktop; phones have the bottom tab bar). The header itself never changes.
  const [headerGone, setHeaderGone] = useState(false);
  // Search mode hides the header row (display: none), which the observer reads as "gone":
  // never float over the search row.
  const floating = headerGone && !searching;
  useEffect(() => {
    const el = headerRef.current;
    if (!el) return;
    const observer = new IntersectionObserver(([entry]) => setHeaderGone(!entry!.isIntersecting));
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  // A phone menu (dimmed page behind it) locks the page scroll until it closes.
  useEffect(() => {
    // Search mode (icon → full-width row) is below 1024px (where the tabs get labels); from there the header has the field itself.
    const phone = openMenu === "search" ? "(max-width: 1023px)" : "(max-width: 767px)";
    if (!openMenu || !window.matchMedia(phone).matches) return;
    const root = document.documentElement;
    const previous = root.style.overflow;
    root.style.overflow = "hidden";
    return () => {
      root.style.overflow = previous;
    };
  }, [openMenu]);
  const headerRef = useRef<HTMLElement>(null);
  // After a navigation the page jumps to the top (ScrollRestoration, a child, runs first). Decide
  // floating now, in the same commit, so a view transition's new snapshot already shows the
  // header nav and the nav morphs into place instead of the floating copy lingering.
  useLayoutEffect(() => {
    const el = headerRef.current;
    if (el) setHeaderGone(el.getBoundingClientRect().bottom < 0);
  }, [location.key]);
  const [headerBottom, setHeaderBottom] = useState(76);
  useLayoutEffect(() => {
    // Scrolled past the header → menus sit at the top of the viewport.
    if (openMenu && headerRef.current)
      setHeaderBottom(Math.max(0, Math.round(headerRef.current.getBoundingClientRect().bottom)));
  }, [openMenu]);

  const items: NavItem[] = [
    { to: "/", label: t.shell.overview, icon: "grid" },
    { to: "/users", label: t.shell.users, icon: "users", count: overview.data?.users.total },
    {
      to: "/invites",
      label: t.shell.invites,
      icon: "ticket",
      count: overview.data?.invites.unused,
    },
  ];

  const user = session.data?.user;
  // The header and the floating nav both carry the account menu; only the visible one opens.
  const accountMenu = (visible: boolean) =>
    user && (
      <AccountMenu
        user={user}
        open={openMenu === "account" && visible}
        onToggle={() => setOpenMenu(openMenu === "account" ? null : "account")}
        onClose={() => setOpenMenu(null)}
        theme={theme}
        onTheme={setTheme}
        lang={lang}
        onLang={(l) => void chooseLang(l)}
        onSignOut={() => signOut.mutate()}
        signingOut={signOut.isPending}
      />
    );
  const shellVars: CSSProperties & Record<`--${string}`, string> = {
    "--header-bottom": `${headerBottom}px`,
    "--menu-top": `${headerBottom + 8}px`,
  };
  return (
    <div className="min-h-dvh bg-page" style={shellVars}>
      {/* Phone: room at the bottom for the floating tab bar. */}
      <div className="mx-auto flex max-w-[1280px] flex-col gap-7 px-4 pt-5 pb-[calc(108px+env(safe-area-inset-bottom))] md:px-8 md:pb-12">
        {/* Phone search mode: the header row becomes the search field + close, so nothing floats over it. */}
        {searching && (
          <header
            ref={headerRef}
            role="search"
            className="sticky top-3 z-20 flex min-h-[52px] items-center gap-2 lg:hidden"
          >
            <QuickSearch autoFocus onDone={() => setOpenMenu(null)} className="min-w-0 flex-1" />
            <IconButton
              icon="x"
              label={t.shell.closeSearch}
              variant="sheet"
              onClick={() => setOpenMenu(null)}
            />
          </header>
        )}
        <header
          ref={searching ? undefined : headerRef}
          className={cn(
            "relative z-20 flex min-h-[52px] flex-nowrap items-center gap-2 md:gap-4",
            searching && "max-lg:hidden",
          )}
        >
          <Wordmark dev={isDevHost(window.location.hostname)} />
          <div className="hidden md:block">
            <NavPills items={items} transitionName={floating ? undefined : "main-nav"} />
          </div>
          <span className="flex-[1_1_24px]" />
          {searchable && (
            <div role="search" className="hidden min-w-[160px] flex-[0_1_320px] lg:block">
              <QuickSearch shortcut={!floating} />
            </div>
          )}
          {searchable && (
            <IconButton
              icon="search"
              label={t.shell.openSearch}
              variant="sheet"
              onClick={() => setOpenMenu("search")}
              className="lg:hidden"
            />
          )}
          {isDevHost(window.location.hostname) && (
            <Chip
              tone="pink"
              icon="code"
              className="h-7 px-2.5 text-[11.5px] font-semibold tracking-[0.06em] max-md:hidden"
            >
              DEV
            </Chip>
          )}
          {accountMenu(!floating)}
        </header>
        {/* Whole page dimmed (also behind a sticky field when scrolled); the field and its results sit above. */}
        {searching && (
          <button
            type="button"
            tabIndex={-1}
            aria-label={t.shell.closeSearch}
            onClick={() => setOpenMenu(null)}
            className="fixed inset-0 z-10 cursor-default bg-scrim lg:hidden"
          />
        )}
        <main className="flex flex-col gap-7">
          <Outlet />
        </main>
      </div>
      {/* Floating nav: slides down when the header is gone, back up when it returns. */}
      <div
        inert={!floating}
        aria-hidden={!floating || undefined}
        className={cn(
          "fixed inset-x-0 top-3 z-30 flex justify-center px-4 transition-[transform,opacity] duration-300 ease-out motion-reduce:transition-none max-md:hidden",
          floating
            ? "translate-y-0 opacity-100"
            : "pointer-events-none -translate-y-[calc(100%+12px)] opacity-0",
        )}
      >
        <div className="flex w-full max-w-[880px] items-center gap-3 rounded-full bg-sheet/85 py-1 pr-1 pl-4 shadow-[var(--shadow-sheet),inset_0_0_0_1px_var(--c-track)] backdrop-blur-md">
          <LogoMark size={24} />
          <NavPills items={items} transitionName={floating ? "main-nav" : undefined} />
          <span className="flex-1" />
          {/* Shrinkable field from 768px: the capsule has room even where the header only fits an icon. */}
          {searchable && (
            <div role="search" className="min-w-0 flex-[0_1_260px]">
              <QuickSearch shortcut={floating} tone="canvas" />
            </div>
          )}
          {accountMenu(floating)}
        </div>
      </div>
      <NavTabBar items={items} />
      <ToastHost />
      {/* New screen → top of the page; back/forward → where the admin left it. */}
      <ScrollRestoration getKey={scrollKey} />
    </div>
  );
}
