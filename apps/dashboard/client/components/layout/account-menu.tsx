import { useEffect, useRef } from "react";
import { useI18n } from "../../i18n";
import type { Lang, ThemePref } from "../../stores/ui-store";
import { Avatar } from "../ui/avatar";
import { Icon, Spinner } from "../ui/icons";
import { Segmented } from "../ui/segmented";

type Props = {
  user: { name: string; email: string };
  open: boolean;
  onToggle: () => void;
  onClose: () => void;
  theme: ThemePref;
  onTheme: (t: ThemePref) => void;
  lang: Lang;
  onLang: (l: Lang) => void;
  onSignOut: () => void;
  signingOut?: boolean;
};

/**
 * Design component 1, account dropdown: 44 pill trigger (avatar 36 + chevron); 304 wide menu, radius 24,
 * sheet shadow. Profile, "Bahasa" (language), "Tampilan" (appearance), then "Keluar" (sign out) under a divider. Both choices apply at
 * once (no Save). Closes on outside click.
 */
export function AccountMenu({
  user,
  open,
  onToggle,
  onClose,
  theme,
  onTheme,
  lang,
  onLang,
  onSignOut,
  signingOut,
}: Props) {
  const { t } = useI18n();
  const label = user.name || user.email;
  // Outside click and Esc close it from the document: the scrim below is position:fixed, which a
  // transformed / backdrop-filtered parent (the floating nav) shrinks to its own box.
  const root = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => !root.current?.contains(e.target as Node) && onClose();
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    document.addEventListener("mousedown", onDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [open, onClose]);
  return (
    <div ref={root} className="relative flex-none">
      <button
        type="button"
        aria-haspopup="true"
        aria-expanded={open}
        aria-controls="menu-akun"
        aria-label={t.shell.accountMenuFor(label)}
        onClick={onToggle}
        className="inline-flex h-11 items-center gap-1.5 rounded-full bg-sheet p-1 text-ink md:pr-3"
      >
        <Avatar seed={user.email} label={label} />
        <Icon
          name="chevdown"
          size={16}
          className={`text-ink2 transition-transform duration-150 max-md:hidden ${open ? "rotate-180" : ""}`}
        />
      </button>
      {open && (
        <>
          <button
            type="button"
            tabIndex={-1}
            aria-label={t.shell.closeMenu}
            onClick={onClose}
            className="fixed inset-0 z-10 cursor-default bg-scrim md:bg-transparent"
          />
          <div
            id="menu-akun"
            role="group"
            aria-label={t.shell.accountMenu}
            className="fixed inset-x-3.5 top-(--menu-top) z-20 flex flex-col gap-4 rounded-menu bg-sheet p-4 shadow-[var(--shadow-sheet),inset_0_0_0_1px_var(--c-track)] md:absolute md:inset-x-auto md:top-[calc(100%+8px)] md:right-0 md:w-[304px]"
          >
            <div className="flex items-center gap-3">
              <Avatar seed={user.email} label={label} size={40} />
              <div className="flex min-w-0 flex-col gap-0.5">
                <span className="truncate text-body font-semibold">{label}</span>
                <span className="truncate text-caption text-ink2">
                  {user.name ? user.email : t.shell.admin}
                </span>
              </div>
            </div>
            <div className="h-px bg-track" />
            <div className="flex flex-col gap-2">
              <span className="inline-flex items-center gap-1.5 text-caption font-medium text-ink2">
                <Icon name="globe" size={16} />
                {t.shell.language}
              </span>
              {/* Language names stay in their own language, whatever the UI shows. */}
              <Segmented
                label={t.shell.language}
                kind="radio"
                stretch
                value={lang}
                onChange={onLang}
                options={[
                  { value: "id", label: "Indonesia" },
                  { value: "en", label: "English" },
                ]}
              />
            </div>
            <div className="flex flex-col gap-2">
              <span className="inline-flex items-center gap-1.5 text-caption font-medium text-ink2">
                <Icon name="sun" size={16} />
                {t.shell.theme}
              </span>
              <Segmented
                label={t.shell.theme}
                kind="radio"
                stretch
                value={theme}
                onChange={onTheme}
                options={[
                  {
                    value: "light",
                    label: (
                      <>
                        <Icon name="sun" size={16} />
                        {t.shell.light}
                      </>
                    ),
                  },
                  {
                    value: "dark",
                    label: (
                      <>
                        <Icon name="moon" size={16} />
                        {t.shell.dark}
                      </>
                    ),
                  },
                  {
                    value: "system",
                    label: (
                      <>
                        <Icon name="monitor" size={16} />
                        {t.shell.system}
                      </>
                    ),
                  },
                ]}
              />
            </div>
            <div className="h-px bg-track" />
            <button
              type="button"
              onClick={onSignOut}
              disabled={signingOut}
              aria-busy={signingOut || undefined}
              className="flex h-11 items-center justify-center gap-2 rounded-full bg-muted px-4 text-body font-medium text-danger-ink hover:bg-danger-soft"
            >
              {signingOut ? <Spinner /> : <Icon name="logout" />}
              {t.shell.signOut}
            </button>
          </div>
        </>
      )}
    </div>
  );
}
