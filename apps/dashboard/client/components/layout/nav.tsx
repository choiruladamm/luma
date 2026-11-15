import { NavLink, useLocation, useNavigation } from "react-router";
import { useSlidingPill } from "../../hooks/use-sliding-pill";
import { useI18n } from "../../i18n";
import { cn } from "../../lib/cn";
import { formatNumber } from "../../lib/format";
import { Icon, type IconName } from "../ui/icons";

export type NavItem = { to: string; label: string; icon: IconName; count?: number };

const isAt = (path: string, to: string) => (to === "/" ? path === "/" : path === to || path.startsWith(`${to}/`));

/**
 * Desktop nav: pills on a sheet track. The ink pill marks the active screen, a sand pill follows
 * the hovered/focused tab (useSlidingPill). The ink pill moves on click, to the navigation's
 * target, without waiting for the screen's chunk.
 */
export function NavPills({ items }: { items: NavItem[] }) {
  const { t } = useI18n();
  const location = useLocation();
  const navigation = useNavigation();
  const path = navigation.location?.pathname ?? location.pathname;
  const active = items.findIndex((item) => isAt(path, item.to));
  const pill = useSlidingPill(active, items.length);

  return (
    <nav aria-label={t.shell.nav} onMouseLeave={pill.onMouseLeave} className="relative flex gap-1 rounded-[26px] bg-sheet p-1">
      <span aria-hidden="true" style={pill.hoverStyle} className={cn("absolute top-1 left-0 h-11 rounded-full bg-muted", pill.slide, pill.hoverVisible ? "opacity-100" : "opacity-0")} />
      <span aria-hidden="true" style={pill.activeStyle} className={cn("absolute top-1 left-0 h-11 rounded-full bg-ink", pill.slide, pill.activeVisible ? "opacity-100" : "opacity-0")} />
      {items.map((item, i) => (
        <NavLink
          key={item.to}
          {...pill.item(i)}
          to={item.to}
          end={item.to === "/"}
          className={cn("relative z-10 inline-flex h-11 items-center rounded-full px-4 text-body no-underline transition-colors duration-200", i === active ? "font-medium text-canvas" : "font-normal text-ink")}
        >
          {item.label}
        </NavLink>
      ))}
    </nav>
  );
}

/** Mobile burger panel (board 11): rows 48 with icon, name, count chip; active = ink pill. */
export function NavPanel({ items, onNavigate }: { items: NavItem[]; onNavigate: () => void }) {
  const { t, locale } = useI18n();
  return (
    <nav id="menu-nav" aria-label={t.shell.nav} className="fixed inset-x-3.5 top-[76px] z-20 rounded-menu bg-sheet p-2 shadow-[var(--shadow-sheet),inset_0_0_0_1px_var(--c-track)]">
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
              {item.count !== undefined && <span className="rounded-full bg-muted px-2.5 py-0.5 text-chip font-medium text-ink tabular-nums">{formatNumber(item.count, locale)}</span>}
            </NavLink>
          </li>
        ))}
      </ul>
    </nav>
  );
}
