import { screen, waitFor, within } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import { renderApp } from "../helpers/render";
import { server } from "../setup";

// The match is wrapped in <mark>, so accessible names can carry a space at its edges.
const countUsersRequests = () => {
  const urls: string[] = [];
  server.events.on("request:start", ({ request }) => {
    if (new URL(request.url).pathname === "/api/users") urls.push(request.url);
  });
  return urls;
};

describe("header quick search", () => {
  afterEach(() => server.events.removeAllListeners());

  it("one character sends nothing; a pause with two shows users, Enter on one opens it", async () => {
    const { user, router } = renderApp("/");
    await within(await screen.findByRole("region", { name: "User terdaftar" })).findByText("48");
    const urls = countUsersRequests();
    const box = screen.getByRole("combobox", { name: "Cari email user" });
    await user.type(box, "u");
    await new Promise((r) => setTimeout(r, 400));
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
