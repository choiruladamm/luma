import { expect, test } from "@playwright/test";

test.describe("English browser", () => {
  test.use({ locale: "en-US" });

  test("opens in English, switches to Indonesian, and keeps the choice after a reload @phone", async ({ page }) => {
    await page.goto("/");
    await expect(page.locator("html")).toHaveAttribute("lang", "en");
    const menu = page.getByRole("button", { name: /^Account menu:/ });
    await expect(menu).toBeVisible();

    await menu.click();
    await page.getByRole("radio", { name: "Indonesia" }).click();
    await expect(page.getByRole("button", { name: /^Menu akun:/ })).toBeVisible();
    await expect(page.locator("html")).toHaveAttribute("lang", "id");

    await page.reload();
    await expect(page.getByRole("button", { name: /^Menu akun:/ })).toBeVisible();
    await expect(page.locator("html")).toHaveAttribute("lang", "id");
  });
});
