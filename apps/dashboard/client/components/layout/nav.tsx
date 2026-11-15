import { NavLink } from "react-router";
import { cn } from "../../lib/cn";
import { Icon, type IconName } from "../ui/icons";

export type NavItem = { to: string; label: string; icon: IconName; count?: number };

/** Desktop nav: pills on a sheet track; active = ink pill. */
export function NavPills({ items }: { items: NavItem[] }) {
  return (
    <nav aria-label="Navigasi admin" className="flex gap-1 rounded-[26px] bg-sheet p-1">
      {items.map((item) => (
        <NavLink
          key={item.to}
          to={item.to}
          end={item.to === "/"}
          className={({ isActive }) => cn("inline-flex h-11 items-center rounded-full px-4 text-body no-underline", isActive ? "bg-ink font-medium text-canvas" : "font-normal text-ink hover:bg-canvas")}
        >
          {item.label}
        </NavLink>
      ))}
    </nav>
  );
}

/** Mobile burger panel (board 11): rows 48 with icon, name, count chip; active = ink pill. */
export function NavPanel({ items, onNavigate }: { items: NavItem[]; onNavigate: () => void }) {
  return (
    <nav id="menu-nav" aria-label="Navigasi admin" className="fixed inset-x-3.5 top-[76px] z-20 rounded-menu bg-sheet p-2 shadow-[var(--shadow-sheet),inset_0_0_0_1px_var(--c-track)]">
      <ul className="m-0 flex list-none flex-col gap-1 p-0">
        {items.map((item) => (
          <li key={item.to}>
            <NavLink
              to={item.to}
              end={item.to === "/"}
              onClick={onNavigate}
              className={({ isActive }) => cn("flex h-12 items-center gap-3 rounded-full px-4 text-body font-medium no-underline", isActive ? "bg-ink text-canvas" : "text-ink hover:bg-canvas")}
            >
              <Icon name={item.icon} size={20} />
              <span className="flex-1">{item.label}</span>
              {item.count !== undefined && <span className="rounded-full bg-muted px-2.5 py-0.5 text-chip font-medium text-ink tabular-nums">{item.count.toLocaleString("id-ID")}</span>}
            </NavLink>
          </li>
        ))}
      </ul>
    </nav>
  );
}
