import type { ThemePref } from "../../stores/ui-store";
import { Avatar } from "../ui/avatar";
import { Icon } from "../ui/icons";
import { Segmented } from "../ui/segmented";

type Props = {
  user: { name: string; email: string };
  open: boolean;
  onToggle: () => void;
  onClose: () => void;
  theme: ThemePref;
  onTheme: (t: ThemePref) => void;
  onSignOut: () => void;
  signingOut?: boolean;
};

/**
 * Komponen 1, Dropdown akun: 44 pill trigger (avatar 36 + chevron); 304 wide menu, radius 24,
 * sheet shadow. Profile, Tampilan, then Keluar under a divider. Closes on outside click.
 * (Language switch dropped: the dashboard is Indonesian only.)
 */
export function AccountMenu({ user, open, onToggle, onClose, theme, onTheme, onSignOut, signingOut }: Props) {
  const label = user.name || user.email;
  return (
    <div className="relative flex-none">
      <button
        type="button"
        aria-haspopup="true"
        aria-expanded={open}
        aria-controls="menu-akun"
        aria-label={`Menu akun: ${label}`}
        onClick={onToggle}
        className="inline-flex h-11 items-center gap-1.5 rounded-full bg-sheet pr-3 pl-1 text-ink"
      >
        <Avatar seed={user.email} label={label} />
        <Icon name="chevdown" size={16} className="text-ink2" />
      </button>
      {open && (
        <>
          <button type="button" tabIndex={-1} aria-label="Tutup menu" onClick={onClose} className="fixed inset-0 z-10 cursor-default bg-scrim md:bg-transparent" />
          <div id="menu-akun" role="group" aria-label="Menu akun" className="fixed inset-x-3.5 top-[76px] z-20 flex flex-col gap-4 rounded-menu bg-sheet p-4 shadow-[var(--shadow-sheet),inset_0_0_0_1px_var(--c-track)] md:absolute md:inset-x-auto md:top-[calc(100%+8px)] md:right-0 md:w-[304px]">
            <div className="flex items-center gap-3">
              <Avatar seed={user.email} label={label} size={40} />
              <div className="flex min-w-0 flex-col gap-0.5">
                <span className="truncate text-body font-semibold">{label}</span>
                <span className="truncate text-caption text-ink2">{user.name ? user.email : "Admin"}</span>
              </div>
            </div>
            <div className="h-px bg-track" />
            <div className="flex flex-col gap-2">
              <span className="inline-flex items-center gap-1.5 text-caption font-medium text-ink2">
                <Icon name="sun" size={16} />
                Tampilan
              </span>
              <Segmented
                label="Tampilan"
                kind="radio"
                stretch
                value={theme}
                onChange={onTheme}
                options={[
                  { value: "light", label: <><Icon name="sun" size={16} />Terang</> },
                  { value: "dark", label: <><Icon name="moon" size={16} />Gelap</> },
                  { value: "system", label: <><Icon name="monitor" size={16} />Sistem</> },
                ]}
              />
            </div>
            <div className="h-px bg-track" />
            <button type="button" onClick={onSignOut} disabled={signingOut} className="flex h-11 items-center justify-center gap-2 rounded-full bg-muted px-4 text-body font-medium text-danger-ink hover:bg-danger-soft">
              <Icon name="logout" />
              {signingOut ? "Lagi keluar…" : "Keluar"}
            </button>
          </div>
        </>
      )}
    </div>
  );
}
