import { screen, waitFor, within } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { elapse, fakeClock, recordRequests } from "../helpers/clock";
import { renderApp } from "../helpers/render";

describe("header quick search", () => {
  it("one character sends nothing; a pause with two shows users, Enter on one opens it", async () => {
    const { user, router } = renderApp("/");
    await within(await screen.findByRole("region", { name: "User terdaftar" })).findByText("48");
    const urls = recordRequests("/api/users");
    const box = screen.getByRole("combobox", { name: "Cari email user" });
    fakeClock();
    await user.type(box, "u");
    await elapse(400);
    expect(urls.filter((u) => u.includes("q="))).toHaveLength(0);

    await user.type(box, "s");
    expect(
      await screen.findByRole("option", {
        name: (n) => n.replace(/\s/g, "").includes("user1@luma.test"),
      }),
    ).toBeInTheDocument();
    expect(urls.filter((u) => u.includes("q=us"))).toHaveLength(1);
    await user.keyboard("{ArrowDown}{Enter}");
    await waitFor(() => expect(router.state.location.pathname).toBe("/users/u1"));
  });

  it("results for older text can't be picked while new text waits for the debounce", async () => {
    const { user, router } = renderApp("/");
    await within(await screen.findByRole("region", { name: "User terdaftar" })).findByText("48");
    const box = screen.getByRole("combobox", { name: "Cari email user" });
    await user.type(box, "us");
    await screen.findByRole("option", {
      name: (n) => n.replace(/\s/g, "").includes("user1@luma.test"),
    });
    await user.type(box, "x");
    await user.keyboard("{ArrowDown}{Enter}");
    await waitFor(() => expect(router.state.location.search).toBe("?q=usx"));
    expect(router.state.location.pathname).toBe("/users");
  });

  it("'see all' opens /users?q= and the header field hides there", async () => {
    const { user, router } = renderApp("/");
    await within(await screen.findByRole("region", { name: "User terdaftar" })).findByText("48");
    await user.keyboard("/");
    const box = screen.getByRole("combobox", { name: "Cari email user" });
    expect(box).toHaveFocus();
    await user.type(box, "us");
    await user.click(await screen.findByRole("option", { name: /Lihat semua hasil/ }));
    await waitFor(() => expect(router.state.location.search).toBe("?q=us"));
    // The shell re-renders after the URL commits: wait for the field to go.
    await waitFor(() =>
      expect(screen.queryByRole("combobox", { name: "Cari email user" })).toBeNull(),
    );
  });
});
