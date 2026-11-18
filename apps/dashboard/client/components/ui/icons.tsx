import {
  Add01Icon,
  AlertCircleIcon,
  ArrowDown01Icon,
  ArrowDown02Icon,
  ArrowLeft01Icon,
  ArrowReloadHorizontalIcon,
  ArrowRight01Icon,
  ArrowRight02Icon,
  ArrowUp02Icon,
  ArrowUpDownIcon,
  Book02Icon,
  Cancel01Icon,
  Clock01Icon,
  CloudIcon,
  CodeIcon,
  ComputerIcon,
  Copy01Icon,
  FilterHorizontalIcon,
  DatabaseIcon,
  GlobeIcon,
  GoogleIcon,
  Loading03Icon,
  GridViewIcon,
  HardDriveIcon,
  Key01Icon,
  Logout01Icon,
  Mail01Icon,
  Menu01Icon,
  Moon02Icon,
  RefreshIcon,
  Search01Icon,
  SmartPhone01Icon,
  SquareLock02Icon,
  Sun03Icon,
  Ticket01Icon,
  Tick02Icon,
  UnavailableIcon,
  UserGroupIcon,
  UserIcon,
} from "@hugeicons/core-free-icons";
import { HugeiconsIcon } from "@hugeicons/react";

// Hugeicons stroke-rounded (free), the same set the mobile app uses. Names follow the board's
// icon list (design component 1) so screens read like the design.
const ICONS = {
  grid: GridViewIcon,
  user: UserIcon,
  users: UserGroupIcon,
  mail: Mail01Icon,
  search: Search01Icon,
  refresh: RefreshIcon,
  key: Key01Icon,
  lock: SquareLock02Icon,
  chev: ArrowRight01Icon,
  chevdown: ArrowDown01Icon,
  arrow: ArrowRight02Icon,
  back: ArrowLeft01Icon,
  sync: ArrowReloadHorizontalIcon,
  cloud: CloudIcon,
  code: CodeIcon,
  menu: Menu01Icon,
  ban: UnavailableIcon,
  copy: Copy01Icon,
  plus: Add01Icon,
  x: Cancel01Icon,
  alert: AlertCircleIcon,
  check: Tick02Icon,
  db: DatabaseIcon,
  drive: HardDriveIcon,
  book: Book02Icon,
  ticket: Ticket01Icon,
  phone: SmartPhone01Icon,
  clock: Clock01Icon,
  down: ArrowDown02Icon,
  up: ArrowUp02Icon,
  sort: ArrowUpDownIcon,
  filter: FilterHorizontalIcon,
  sun: Sun03Icon,
  moon: Moon02Icon,
  monitor: ComputerIcon,
  logout: Logout01Icon,
  google: GoogleIcon,
  globe: GlobeIcon,
  loading: Loading03Icon,
} as const;

export type IconName = keyof typeof ICONS;

/** Decorative unless `label` is given (then role="img" + aria-label). */
export function Icon({ name, size = 18, strokeWidth = 1.8, label, className }: { name: IconName; size?: number; strokeWidth?: number; label?: string; className?: string }) {
  return (
    <HugeiconsIcon
      icon={ICONS[name]}
      size={size}
      strokeWidth={strokeWidth}
      className={className ? `flex-none ${className}` : "flex-none"}
      role={label ? "img" : undefined}
      aria-label={label}
      aria-hidden={label ? undefined : true}
      focusable="false"
    />
  );
}

/** Busy indicator for buttons: replaces the button's icon, or sits left of its label. Still under reduced motion. */
export const Spinner = ({ size = 18 }: { size?: number }) => <Icon name="loading" size={size} className="motion-safe:animate-spin" />;
