import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { Providers } from "./app/providers";
import { applyLang, getI18n, loadLang, resolveLang } from "./i18n";
import { applyTheme, useUiStore } from "./stores/ui-store";
import "./styles/app.css";

// Before the first paint, so a saved light/dark choice doesn't flash the other theme.
applyTheme(useUiStore.getState().theme);

// English loads before the first render, so it never flashes Indonesian. A failed load renders
// Indonesian instead of nothing.
void loadLang(resolveLang(useUiStore.getState().lang))
  .catch(() => undefined)
  .then(() => {
    applyLang(getI18n().lang);
    createRoot(document.getElementById("root")!).render(
      <StrictMode>
        <Providers />
      </StrictMode>,
    );
    // English is the only lazy chunk. Fetch it once the page is idle, so the first switch from the
    // account menu doesn't sit waiting on the network (or on Vite's first transform in dev).
    const idle = window.requestIdleCallback ?? ((run: () => void) => setTimeout(run, 2000));
    idle(() => void loadLang("en").catch(() => undefined));
  });
