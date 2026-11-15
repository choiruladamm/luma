/**
 * `text` with the first case-insensitive match of `q` marked by a yellow stabilo underlay
 * (the accent; `bg-transparent` drops the browser's own <mark> background). User data stays as
 * typed; only the marking is added.
 */
export function Highlight({ text, q }: { text: string; q?: string }) {
  const at = q ? text.toLowerCase().indexOf(q.toLowerCase()) : -1;
  if (!q || at < 0) return <>{text}</>;
  return (
    <>
      {text.slice(0, at)}
      <mark className="bg-transparent bg-[linear-gradient(transparent_55%,var(--c-accent)_55%)] text-inherit">{text.slice(at, at + q.length)}</mark>
      {text.slice(at + q.length)}
    </>
  );
}
