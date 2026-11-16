import { type CSSProperties, useLayoutEffect, useRef, useState } from "react";

type Box = { x: number; w: number };

const place = (box: Box | undefined): CSSProperties => ({ width: box?.w ?? 0, transform: `translateX(${box?.x ?? 0}px)` });

/**
 * Sliding indicators for a row of tabs (nav, Segmented): one pill under the active item and one
 * under the hovered/focused item, moved with transform + width instead of jumping. The hover
 * pill fades out in place and hides over the active item. No slide on the first measure, and
 * none under prefers-reduced-motion (`slide` carries motion-reduce). Items are re-measured when
 * their size changes (language switch, fonts loading).
 *
 * Usage: `item(i)` on each item (ref + hover handlers), `onMouseLeave` on the row, and two
 * absolutely positioned spans with `activeStyle` / `hoverStyle` behind items that sit above them.
 */
export function useSlidingPill(active: number, count: number) {
  const items = useRef<(HTMLElement | null)[]>([]);
  const [boxes, setBoxes] = useState<Box[]>([]);
  const [hover, setHover] = useState<number | null>(null);
  const [lastHover, setLastHover] = useState(-1);
  const [animate, setAnimate] = useState(false);

  useLayoutEffect(() => {
    const measure = () => setBoxes(items.current.slice(0, count).map((el) => ({ x: el?.offsetLeft ?? 0, w: el?.offsetWidth ?? 0 })));
    measure();
    const frame = requestAnimationFrame(() => setAnimate(true));
    const observer = new ResizeObserver(measure);
    items.current.slice(0, count).forEach((el) => el && observer.observe(el));
    return () => {
      cancelAnimationFrame(frame);
      observer.disconnect();
    };
  }, [count]);

  const enter = (i: number) => {
    setHover(i);
    if (i !== active) setLastHover(i);
  };

  return {
    item: (i: number) => ({
      ref: (el: HTMLElement | null) => {
        items.current[i] = el;
      },
      onMouseEnter: () => enter(i),
      onFocus: () => enter(i),
      onBlur: () => setHover(null),
    }),
    onMouseLeave: () => setHover(null),
    activeStyle: place(boxes[active]),
    hoverStyle: place(boxes[lastHover]),
    activeVisible: active >= 0 && !!boxes[active]?.w,
    hoverVisible: hover !== null && hover !== active && !!boxes[lastHover]?.w,
    /** Transition classes, only after the first measure. */
    slide: animate ? "transition-[transform,width,opacity] duration-200 ease-out motion-reduce:transition-none" : "",
  };
}
