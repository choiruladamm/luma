import { expect, test } from "@playwright/test";

test.describe("English browser", () => {
  test.use({ locale: "en-US" });

  test("opens every screen in English, switches to Indonesian, and keeps the choice after a reload @phone", async ({ page }) => {
    await page.goto("/");
    await expect(page.locator("html")).toHaveAttribute("lang", "en");
    await expect(page.getByRole("heading", { name: "Overview", level: 1 })).toBeVisible();
    await page.goto("/users");
    await expect(page.getByRole("heading", { name: "Users", level: 1 })).toBeVisible();
    await expect(page.getByRole("navigation", { name: "Pagination" })).toBeVisible();
    await page.goto("/invites");
    await expect(page.getByRole("heading", { name: "Invites", level: 1 })).toBeVisible();
    await expect(page.getByText("One code per account")).toBeVisible();

    const menu = page.getByRole("button", { name: /^Account menu:/ });
    await expect(menu).toBeVisible();

    await menu.click();
    await page.getByRole("radio", { name: "Indonesia" }).click();
    await expect(page.getByRole("heading", { name: "Undangan", level: 1 })).toBeVisible();
    await expect(page.locator("html")).toHaveAttribute("lang", "id");

    await page.reload();
    await expect(page.getByRole("button", { name: /^Menu akun:/ })).toBeVisible();
    await expect(page.locator("html")).toHaveAttribute("lang", "id");
  });
});
