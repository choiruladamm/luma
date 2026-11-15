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
          className={cn("relative z-10 inline-flex h-11 items-center gap-2 rounded-full pr-4 pl-3.5 text-body no-underline transition-colors duration-200", i === active ? "font-medium text-canvas" : "font-normal text-ink")}
        >
          <Icon name={item.icon} size={18} />
          {item.label}
        </NavLink>
      ))}
    </nav>
  );
}

/**
 * Phone nav (<768px): a floating tab bar at the bottom, icon + label + count, one tap to any
 * screen. The ink pill slides to the navigation target like the desktop nav (useSlidingPill).
 */
export function NavTabBar({ items }: { items: NavItem[] }) {
  const { t, locale } = useI18n();
  const location = useLocation();
  const navigation = useNavigation();
  const path = navigation.location?.pathname ?? location.pathname;
  const active = items.findIndex((item) => isAt(path, item.to));
  const pill = useSlidingPill(active, items.length);

  return (
    <nav aria-label={t.shell.nav} className="fixed inset-x-3 bottom-[calc(12px+env(safe-area-inset-bottom))] z-30 flex rounded-full bg-sheet p-1.5 shadow-[var(--shadow-sheet),inset_0_0_0_1px_var(--c-track)] md:hidden">
      <span aria-hidden="true" style={pill.activeStyle} className={cn("absolute top-1.5 left-0 h-14 rounded-full bg-ink", pill.slide, pill.activeVisible ? "opacity-100" : "opacity-0")} />
      {items.map((item, i) => (
        <NavLink
          key={item.to}
          ref={pill.item(i).ref}
          to={item.to}
          end={item.to === "/"}
          className={cn("relative z-10 flex h-14 min-w-0 flex-1 flex-col items-center justify-center gap-1 rounded-full no-underline transition-colors duration-200", i === active ? "text-canvas" : "text-ink2")}
        >
          <span className="relative">
            <Icon name={item.icon} size={22} />
            {item.count !== undefined && (
              <span className={cn("absolute -top-1.5 left-[14px] min-w-5 rounded-full px-1.5 text-center text-[10.5px] leading-[18px] font-semibold tabular-nums", i === active ? "bg-canvas text-ink" : "bg-muted text-ink")}>
                {formatNumber(item.count, locale)}
              </span>
            )}
          </span>
          <span className={cn("max-w-full truncate px-1 text-[12px] leading-none", i === active ? "font-semibold" : "font-medium")}>{item.label}</span>
        </NavLink>
      ))}
    </nav>
  );
}
