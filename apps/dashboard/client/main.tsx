import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { Providers } from "./app/providers";
import { applyTheme, useUiStore } from "./stores/ui-store";
import "./styles/app.css";

// Before the first paint, so a saved light/dark choice doesn't flash the other theme.
applyTheme(useUiStore.getState().theme);

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <Providers />
  </StrictMode>,
);
