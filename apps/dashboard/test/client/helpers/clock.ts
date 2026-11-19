import { act } from "@testing-library/react";
import { onTestFinished, vi } from "vitest";
import { server } from "../setup";

/**
 * URLs of the API requests started from now on, optionally only those to `path`. The listener is
 * removed when the test ends, pass or fail, and never touches listeners set up elsewhere.
 */
export function recordRequests(path?: string) {
  const urls: string[] = [];
  const listener = ({ request }: { request: Request }) => {
    if (!path || new URL(request.url).pathname === path) urls.push(request.url);
  };
  server.events.on("request:start", listener);
  onTestFinished(() => server.events.removeListener("request:start", listener));
  return urls;
}

/**
 * Fakes the clock for this test (it still ticks in real time, so user-event and `findBy` work).
 * Install it before the debounce or refetch under test schedules its timer.
 */
export function fakeClock() {
  vi.useFakeTimers({ shouldAdvanceTime: true });
  onTestFinished(() => {
    vi.useRealTimers();
  });
}

/** Runs every timer due within `ms`, and the renders, queries, and requests they start. */
export const elapse = (ms: number) => act(() => vi.advanceTimersByTimeAsync(ms));
