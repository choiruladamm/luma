import type { ButtonHTMLAttributes, ReactNode } from "react";
import { Link, type LinkProps } from "react-router";
import { cn } from "../../lib/cn";
import { Icon, type IconName, Spinner } from "./icons";

// Komponen 1, Tombol: one yellow primary per screen; full danger only inside confirm dialogs.
export type ButtonVariant = "primary" | "secondary" | "sheet" | "danger" | "danger-soft";

const VARIANTS: Record<ButtonVariant, string> = {
  primary:
    "bg-accent text-on-accent border-[1.5px] border-outline shadow-primary hover:brightness-[1.03] active:translate-y-[2px] active:shadow-none",
  secondary: "bg-muted text-ink hover:bg-track",
  sheet: "bg-sheet text-ink hover:bg-canvas",
  danger: "bg-danger text-on-danger hover:brightness-105",
  "danger-soft": "bg-danger-soft text-danger-ink hover:brightness-[0.98]",
};

export function buttonClass(variant: ButtonVariant = "secondary", { size = "md", iconOnly = false } = {}) {
  return cn(
    "inline-flex items-center justify-center gap-2 rounded-full font-sans text-body font-medium whitespace-nowrap no-underline select-none",
    "transition-[background-color,filter,transform] duration-100",
    "disabled:pointer-events-none disabled:bg-muted disabled:text-ink2 disabled:shadow-none disabled:border-transparent",
    size === "lg" ? "h-12" : "h-11",
    iconOnly ? (size === "lg" ? "w-12" : "w-11") : "px-5",
    VARIANTS[variant],
  );
}

type Common = { variant?: ButtonVariant; icon?: IconName; size?: "md" | "lg"; children?: ReactNode };

/**
 * `loading`: the request is running. Disabled (board: sand + ink2) and aria-busy; the spinner
 * takes the icon's place, or goes left of the label when there is no icon. The label stays.
 */
export function Button({ variant, icon, size, loading, disabled, className, children, type = "button", ...props }: Common & { loading?: boolean } & ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button type={type} disabled={disabled || loading} aria-busy={loading || undefined} className={cn(buttonClass(variant, { size }), className)} {...props}>
      {loading ? <Spinner /> : icon && <Icon name={icon} />}
      {children}
    </button>
  );
}

/** Icon-only button: the label is required (aria-label), the icon is decorative. */
export function IconButton({ variant = "secondary", icon, label, className, size, loading, disabled, ...props }: { icon: IconName; label: string; variant?: ButtonVariant; size?: "md" | "lg"; loading?: boolean } & ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button type="button" aria-label={label} disabled={disabled || loading} aria-busy={loading || undefined} className={cn(buttonClass(variant, { size, iconOnly: true }), className)} {...props}>
      {loading ? <Spinner /> : <Icon name={icon} />}
    </button>
  );
}

export function ButtonLink({ variant, icon, size, className, children, ...props }: Common & LinkProps) {
  return (
    <Link className={cn(buttonClass(variant, { size }), className)} {...props}>
      {icon && <Icon name={icon} />}
      {children}
    </Link>
  );
}
