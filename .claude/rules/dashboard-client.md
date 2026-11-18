---
paths: ["apps/dashboard/client/**", "apps/dashboard/test/client/**"]
---

# Dashboard client (React SPA)

React Router, TanStack Query over `hc<AppType>()`, RHF + `zod/mini`, TanStack Table, Zustand. No Axios, no React Router actions. Files are kebab-case.

## Structure

- One-way flow: `pages → (feature hooks + queries) → api → lib/api-client`. Components only take props. `api/`, `queries/`, `hooks/` never import another feature; a page may compose another feature's components and queries.
- `features/*/api/`: raw `hc` calls through `unwrap()` → data or `ApiError`, no React. `queries/`: the only place for `useQuery`/`useMutation`, keys in `query-keys.ts`. `hooks/`: client logic that never calls the API. `schemas/`: `zod/mini` (full zod doubled the Users chunk), mirroring worker limits; the worker stays the authority.
- `client/` imports from `worker/` with `import type` only. Better Auth routes aren't in `AppType`; `features/auth/api` uses plain `fetch`.
- `app/routes.tsx`: every screen is `lazy` with `ErrorBoundary: ScreenError`; error screens in `app/route-error.tsx` are imported eagerly so they render when a chunk fails. A route `loader` only prefetches that screen's queries (`prefetch()` in `app/prefetch.ts`) and returns `null`; the hooks own the data.
- Keep the TanStack Query defaults in `app/query-client.ts` (no focus refetch, no polling): the dashboard shares the backend's free-tier quota.
- Zustand (`stores/`) holds UI state only, never API data.
- Static file headers live in `public/_headers` (static files skip the Worker).

## UI

- Board "14 · Admin web" in the Stabilo canvas. Tokens in `client/styles/app.css` (CSS variables per theme, mapped to Tailwind colors like `bg-sheet`, `text-ink2`); components use tokens, never a hex.
- Reuse `components/ui` (Button, Chip, Card/StatCard, Segmented, Dialog, DataTable, Toast, states). Icons via `<Icon name>` (Hugeicons stroke-rounded). Tab rows slide their pills through `hooks/use-sliding-pill.ts`.
- `Dialog` is a bottom sheet below 768px, so dialogs need no phone layout.
- Inside the floating nav (transform + backdrop-filter) a `position: fixed` child is sized to the capsule, not the viewport: close popovers with a document listener (as AccountMenu, Select, QuickSearch do), not a fixed scrim alone.
- Nav links use `viewTransition`; only the visible nav copy carries `view-transition-name: main-nav` (two elements with one name break the transition).
- Table URL setters pass `preventScrollReset`; `Pagination` scrolls to the table itself.
- A button whose request is running takes `loading` (Button/IconButton): disabled + spinner in the icon's place, label unchanged.

## Copy

Copy lives in `client/i18n/id.ts` (source; its shape is the `Messages` type) and `en.ts` (own lazy chunk). Components use `useI18n()`; code outside React (mutation callbacks → toasts) uses `getI18n()`. Formatters in `lib/format` take the locale explicitly. API errors render via `errorText(error, t)` from the error `code`. User data (names, emails, user agents, codes) is never translated. Rules: `docs/dashboard.md` (Localization).

## Client tests

- `unit/` covers `lib`, stores, hooks, `components/ui`; `integration/` per feature renders the whole app (`helpers/render.tsx`: memory router over the real routes, preloads lazy chunks) with the API mocked by MSW (`helpers/handlers.ts`). Unhandled requests fail the test. Loaders do nothing in tests (no query client registered).
- user-event stubs the clipboard: read it back with `navigator.clipboard.readText()`.
- The phone tab bar is always in the DOM (CSS hides it on desktop), so a count can appear twice: wait on the stat card (`within(region).findByText`), not the bare text.
- `setup.ts` pins the language to `id`, so assertions use Indonesian copy; English is covered by `unit/i18n.test.ts` and the language switch test.
