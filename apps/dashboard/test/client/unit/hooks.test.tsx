import { act, renderHook } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { useCopyToClipboard } from "../../../client/hooks/use-copy-to-clipboard";
import { useDebounce } from "../../../client/hooks/use-debounce";
import { useMediaQuery } from "../../../client/hooks/use-media-query";

afterEach(() => vi.useRealTimers());

describe("useDebounce", () => {
  it("only settles after the value stops changing", () => {
    vi.useFakeTimers();
    const { result, rerender } = renderHook(({ v }) => useDebounce(v, 300), {
      initialProps: { v: "a" },
    });
    rerender({ v: "ab" });
    act(() => {
      vi.advanceTimersByTime(200);
    });
    rerender({ v: "abc" });
    act(() => {
      vi.advanceTimersByTime(200);
    });
    expect(result.current).toBe("a");
    act(() => {
      vi.advanceTimersByTime(100);
    });
    expect(result.current).toBe("abc");
  });
});

describe("useCopyToClipboard", () => {
  it("writes to the clipboard and resets the copied state", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    const writeText = vi.fn<() => void>().mockResolvedValue(undefined);
    Object.defineProperty(navigator, "clipboard", { value: { writeText }, configurable: true });
    const { result } = renderHook(() => useCopyToClipboard(2000));
    await act(() => result.current.copy("LUMA-AAAAA-BBBBB"));
    expect(writeText).toHaveBeenCalledWith("LUMA-AAAAA-BBBBB");
    expect(result.current.copied).toBe("LUMA-AAAAA-BBBBB");
    act(() => {
      vi.advanceTimersByTime(2000);
    });
    expect(result.current.copied).toBeNull();
  });
});

describe("useMediaQuery", () => {
  it("follows matchMedia and its change events", () => {
    const listeners = new Set<() => void>();
    let matches = false;
    vi.spyOn(window, "matchMedia").mockImplementation(
      (q) =>
        ({
          get matches() {
            return matches;
          },
          media: q,
          addEventListener: (_: string, l: () => void) => listeners.add(l),
          removeEventListener: (_: string, l: () => void) => listeners.delete(l),
        }) as unknown as MediaQueryList,
    );
    const { result } = renderHook(() => useMediaQuery("(max-width: 767px)"));
    expect(result.current).toBe(false);
    matches = true;
    act(() => listeners.forEach((l) => l()));
    expect(result.current).toBe(true);
  });
});
