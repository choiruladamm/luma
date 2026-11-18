/**
 * `text` with the first case-insensitive match of `q` marked by a yellow stabilo underlay
 * (the accent; `bg-transparent` drops the browser's own <mark> background). Dark mode fills the
 * whole mark with on-accent text (`--c-mark-*` in app.css). User data stays as typed.
 */
export function Highlight({ text, q }: { text: string; q?: string }) {
  const at = q ? text.toLowerCase().indexOf(q.toLowerCase()) : -1;
  if (!q || at < 0) return <>{text}</>;
  return (
    <>
      {text.slice(0, at)}
      <mark className="rounded-[3px] bg-transparent bg-[linear-gradient(transparent_var(--c-mark-from),var(--c-accent)_var(--c-mark-from))] text-[color:var(--c-mark-ink,inherit)]">
        {text.slice(at, at + q.length)}
      </mark>
      {text.slice(at + q.length)}
    </>
  );
}
