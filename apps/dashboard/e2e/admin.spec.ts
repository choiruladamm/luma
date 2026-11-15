import { expect, test } from "@playwright/test";

// One local Worker + D1 per run (global-setup). Tests run in order and share that state.
test.describe.configure({ mode: "serial" });

test("signed out: the login screen, and the API refuses without a session", async ({ browser }) => {
  const context = await browser.newContext({ storageState: { cookies: [], origins: [] } });
  const page = await context.newPage();
  await page.goto("/users");
  await expect(page).toHaveURL(/\/login$/);
  await expect(page.getByRole("heading", { name: "Masuk" })).toBeVisible();
  const res = await page.request.get("/api/users");
  expect(res.status()).toBe(401);
  await context.close();
});

test("security headers on the SPA and the API", async ({ page }) => {
  const html = await page.request.get("/");
  const api = await page.request.get("/api/overview");
  // vite dev serves the SPA itself; public/_headers applies in production, the Worker's middleware here.
  expect(api.headers()["content-security-policy"]).toBe("default-src 'self'; frame-ancestors 'none'");
  expect(api.headers()["x-content-type-options"]).toBe("nosniff");
  expect(html.ok()).toBe(true);
});

test("overview shows the seeded numbers", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Ringkasan" })).toBeVisible();
  const stat = (label: string) => page.getByRole("region", { name: label });
  await expect(stat("User terdaftar")).toContainText("5");
  await expect(stat("Di-ban")).toContainText("1");
  await expect(stat("Kode undangan")).toContainText("2");
  await expect(page.getByText("10.000", { exact: true })).toBeVisible();
  await expect(page.getByRole("table", { name: "User yang baru daftar" }).getByRole("link", { name: /rara.anindya@e2e.local/ })).toBeVisible();
});

test("search, open a user, ban, then unban from the banner", async ({ page }) => {
  await page.goto("/users");
  await page.getByRole("searchbox", { name: "Cari email", exact: true }).fill("sekar");
  await expect(page).toHaveURL(/\?q=sekar$/);
  await page.getByRole("link", { name: /sekar.ayu@e2e.local/ }).click();
  await expect(page.getByRole("heading", { name: "sekar.ayu@e2e.local" })).toBeVisible();
  await expect(page.getByText("Google", { exact: true })).toBeVisible();

  await page.getByRole("button", { name: "Ban user" }).click();
  const dialog = page.getByRole("dialog");
  await expect(dialog.getByText("Masuk, backup, dan sync tetap jalan")).toBeVisible();
  await dialog.getByRole("button", { name: "Ban user" }).click();
  await expect(page.getByText("User ini lagi di-ban")).toBeVisible();
  await expect(page.getByRole("status").filter({ hasText: "sekar.ayu@e2e.local di-ban" })).toBeVisible();

  await page.reload();
  await expect(page.getByText("User ini lagi di-ban")).toBeVisible();
  await page.getByRole("button", { name: "Buka ban" }).first().click();
  await expect(page.getByText("User ini lagi di-ban")).toBeHidden();
  await expect(page.getByRole("button", { name: "Ban user" })).toBeVisible();
});

test("Esc closes the ban dialog without banning", async ({ page }) => {
  await page.goto("/users/e2e-4");
  await page.getByRole("button", { name: "Ban user" }).click();
  await expect(page.getByRole("dialog")).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(page.getByRole("dialog")).toBeHidden();
  await page.reload();
  await expect(page.getByText("User ini lagi di-ban")).toBeHidden();
});

test("create an invite code, copy it, then delete it", async ({ page, context }) => {
  await context.grantPermissions(["clipboard-read", "clipboard-write"]);
  await page.goto("/invites");
  await expect(page.getByRole("tab", { name: /Belum dipakai\s*2/ })).toBeVisible();
  await page.getByRole("button", { name: "Bikin kode" }).click();
  const dialog = page.getByRole("dialog");
  const code = (await dialog.locator(".font-mono").first().textContent())!.trim();
  expect(code).toMatch(/^LUMA-[2-9A-HJ-NP-Z]{5}-[2-9A-HJ-NP-Z]{5}$/);
  await dialog.getByRole("button", { name: "Salin kode" }).click();
  await expect(dialog.getByRole("button", { name: "Udah disalin" })).toBeVisible();
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(code);
  await dialog.getByRole("button", { name: "Selesai" }).click();

  await expect(page.getByRole("tab", { name: /Belum dipakai\s*3/ })).toBeVisible();
  await page.getByRole("button", { name: `Hapus ${code}` }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Hapus kode" }).click();
  await expect(page.getByRole("tab", { name: /Belum dipakai\s*2/ })).toBeVisible();
  await expect(page.getByRole("button", { name: `Hapus ${code}` })).toHaveCount(0);
});

test("used codes can't be deleted", async ({ page }) => {
  await page.goto("/invites");
  await page.getByRole("tab", { name: /Udah dipakai/ }).click();
  await expect(page.getByRole("button", { name: /^Hapus LUMA-USED/ })).toHaveCount(0);
  await expect(page.getByRole("link", { name: "rara.anindya@e2e.local" })).toBeVisible();
});

test("the theme choice survives a reload", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: /Menu akun/ }).click();
  await page.getByRole("radio", { name: "Gelap" }).click();
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
  await page.reload();
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
});

test("phone: bottom tab bar, user cards, and the header search @phone", async ({ page }) => {
  test.skip(test.info().project.name !== "phone", "phone layout only");
  await page.goto("/");
  const tabs = page.getByRole("navigation", { name: "Navigasi admin" });
  await expect(tabs.getByRole("link", { name: /Ringkasan/ })).toHaveAttribute("aria-current", "page");
  await tabs.getByRole("link", { name: /User/ }).click();
  await expect(page).toHaveURL(/\/users$/);
  await expect(page.getByRole("list", { name: "Daftar user" }).getByRole("link", { name: /rara.anindya@e2e.local/ })).toBeVisible();

  // Search mode replaces the header row; the page behind can't scroll while it's open.
  await page.goto("/invites");
  await page.getByRole("button", { name: "Buka pencarian" }).click();
  const box = page.getByRole("combobox", { name: "Cari email user" });
  await expect(box).toBeFocused();
  await expect(page.locator("html")).toHaveCSS("overflow", "hidden");
  await box.fill("sekar");
  await page.getByRole("option", { name: /sekar.ayu@e2e.local/ }).click();
  await expect(page).toHaveURL(/\/users\/[^/]+$/);
  await expect(page.locator("html")).not.toHaveCSS("overflow", "hidden");
});

test("users: filter, sort by a column, and the state survives a reload", async ({ page }) => {
  test.skip(test.info().project.name !== "desktop", "desktop toolbar");
  await page.goto("/users");
  await page.getByRole("button", { name: /^Filter$/ }).click();
  await page.getByRole("dialog", { name: "Filter user" }).getByRole("button", { name: /^Status:/ }).click();
  await page.getByRole("option", { name: "Di-ban" }).click();
  await expect(page).toHaveURL(/\?status=banned$/);
  const table = page.getByRole("table", { name: "Daftar user" });
  await expect(table.getByRole("link", { name: /bayu.w@e2e.local/ })).toBeVisible();
  await expect(table.getByRole("link", { name: /rara.anindya@e2e.local/ })).toHaveCount(0);

  await page.getByRole("button", { name: "Hapus filter Status: Di-ban" }).click();
  await page.getByRole("button", { name: /^File/ }).click();
  await expect(page).toHaveURL(/\?sort=r2$/);
  await expect(page.getByRole("columnheader", { name: /^File/ })).toHaveAttribute("aria-sort", "descending");
  await page.reload();
  await expect(page.getByRole("columnheader", { name: /^File/ })).toHaveAttribute("aria-sort", "descending");
  await expect(page.getByRole("navigation", { name: "Paginasi" })).toContainText("dari 5");
});

test("desktop: a compact nav floats in once the header scrolls away, and its tabs navigate", async ({ page }) => {
  test.skip(test.info().project.name !== "desktop", "floating nav is desktop only");
  await page.setViewportSize({ width: 1440, height: 480 });
  await page.goto("/");
  // DOM order: header nav, floating nav, phone tab bar. CSS locator: the hidden copy is aria-hidden.
  const floating = page.locator("nav[aria-label='Navigasi admin']").nth(1);
  await expect(floating).not.toBeInViewport();
  await page.evaluate(() => window.scrollTo(0, 600));
  await expect(floating).toBeInViewport();
  await floating.getByRole("link", { name: /Undangan/ }).click();
  await expect(page).toHaveURL(/\/invites$/);
  // The new screen starts at the top: the header nav is back and the floating copy is hidden again.
  await expect(page.getByRole("heading", { name: "Undangan", level: 1 })).toBeInViewport();
});
