import { Hono } from "hono";
import type { AppEnv } from "../../env";
import { deleteAccount, page, privacy } from "./pages";

/** Static pages the App Store and Play Store require (docs/backend.md, Authentication and accounts). */
export const legal = new Hono<AppEnv>()
  .get("/privacy", (c) =>
    c.html(page("privacy", "Privacy Policy", c.env.CONTACT_EMAIL, privacy(c.env.CONTACT_EMAIL))),
  )
  .get("/account/delete", (c) =>
    c.html(
      page(
        "delete",
        "Delete your account",
        c.env.CONTACT_EMAIL,
        deleteAccount(c.env.CONTACT_EMAIL),
      ),
    ),
  );
