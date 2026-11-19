import { screen, waitFor, within } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { describe, expect, it, onTestFinished } from "vitest";
import { elapse, fakeClock, recordRequests } from "../helpers/clock";
import * as fx from "../helpers/fixtures";
import { API, apiError } from "../helpers/handlers";
import { renderApp } from "../helpers/render";
import { server } from "../setup";

const BOX = { name: "Cari email user" };

async function openHome() {
  const app = renderApp("/");
  await within(await screen.findByRole("region", { name: "User terdaftar" })).findByText("48");
  return { ...app, box: screen.getByRole("combobox", BOX) };
}

/** Users list that answers `/api/users` with `items`, whatever the query. */
const answerWith = (items: ReturnType<typeof fx.user>[]) =>
  server.use(http.get(`${API}/users`, () => HttpResponse.json(fx.usersPage(items))));

/** A response gate: requests wait on it until the test ends, so none is left to abort. */
function held() {
  const gate = Promise.withResolvers<void>();
  onTestFinished(() => gate.resolve());
  return gate.promise;
}

const selected = () =>
  screen.getAllByRole("option").map((o) => o.getAttribute("aria-selected") === "true");

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

  describe("list states", () => {
    it("shows the error copy once the search settles on a failed request", async () => {
      server.use(http.get(`${API}/users`, () => apiError(429, "RATE_LIMITED")));
      const { user, box } = await openHome();
      await user.type(box, "us");
      expect(
        await screen.findByText("Terlalu banyak permintaan. Coba lagi sebentar."),
      ).toBeInTheDocument();
      expect(screen.queryByRole("option")).toBeNull();
    });

    it("shows the no-match copy for an empty answer, and Enter still opens the full search", async () => {
      answerWith([]);
      const { user, router, box } = await openHome();
      await user.type(box, "zz");
      expect(await screen.findByText("Gak ada email yang cocok sama “zz”")).toBeInTheDocument();
      expect(screen.queryByRole("option")).toBeNull();
      await user.keyboard("{Enter}");
      await waitFor(() => expect(router.state.location.search).toBe("?q=zz"));
      expect(router.state.location.pathname).toBe("/users");
    });

    it("shows skeleton rows, not no-match copy, while debouncing and while the request is pending", async () => {
      const gate = held();
      server.use(
        http.get(`${API}/users`, async () => {
          await gate;
          return HttpResponse.json(fx.usersPage([]));
        }),
      );
      const { user, box } = await openHome();
      fakeClock();
      await user.type(box, "us");
      const list = screen.getByRole("listbox", { name: "Hasil cari user" });
      // Debouncing: nothing sent yet.
      expect(list.querySelectorAll("li[aria-hidden='true']")).toHaveLength(2);
      await elapse(400);
      // Request in flight.
      expect(list.querySelectorAll("li[aria-hidden='true']")).toHaveLength(2);
      expect(screen.queryByText(/Gak ada email yang cocok/)).toBeNull();
      expect(screen.queryByRole("option")).toBeNull();
    });

    it("hides the previous search's results while the next one loads", async () => {
      const gate = held();
      server.use(
        http.get(`${API}/users`, async ({ request }) => {
          if (new URL(request.url).searchParams.get("q") === "usx") await gate;
          return HttpResponse.json(fx.usersPage([fx.user(1), fx.user(2)]));
        }),
      );
      const { user, box } = await openHome();
      await user.type(box, "us");
      await screen.findAllByRole("option");
      fakeClock();
      await user.type(box, "x");
      await elapse(400); // debounce passed, placeholder data (the "us" page) is on screen
      expect(screen.queryByRole("option")).toBeNull();
      expect(
        screen
          .getByRole("listbox", { name: "Hasil cari user" })
          .querySelectorAll("li[aria-hidden='true']"),
      ).toHaveLength(2);
    });
  });

  describe("Enter", () => {
    it("opens the user directly on an exact email, ignoring case and a mailto: prefix", async () => {
      answerWith([fx.user(1)]);
      const { user, router, box } = await openHome();
      await user.type(box, "mailto:User1@Luma.test");
      await screen.findAllByRole("option");
      await user.keyboard("{Enter}");
      await waitFor(() => expect(router.state.location.pathname).toBe("/users/u1"));
      expect(box).toHaveValue("");
    });

    it("opens the full search when the first result is only a prefix match", async () => {
      const { user, router, box } = await openHome();
      await user.type(box, "user1");
      await screen.findAllByRole("option");
      await user.keyboard("{Enter}");
      await waitFor(() => expect(router.state.location.search).toBe("?q=user1"));
      expect(router.state.location.pathname).toBe("/users");
    });

    it("opens the full search on an exact email typed before the search settled", async () => {
      answerWith([fx.user(1)]);
      const { user, router, box } = await openHome();
      fakeClock();
      await user.type(box, "user1@luma.test{Enter}");
      await waitFor(() => expect(router.state.location.search).toBe("?q=user1%40luma.test"));
      expect(router.state.location.pathname).toBe("/users");
    });

    it("does nothing below two characters", async () => {
      const { user, router, box } = await openHome();
      await user.type(box, "u{Enter}");
      expect(router.state.location.pathname).toBe("/");
      expect(box).toHaveValue("u");
    });
  });

  describe("arrow keys", () => {
    it("moves down through users and 'see all', wrapping to the first; Enter on 'see all' opens the search", async () => {
      const { user, router, box } = await openHome();
      await user.type(box, "us");
      await screen.findAllByRole("option");
      expect(selected()).toEqual([false, false, false]);
      await user.keyboard("{ArrowDown}");
      expect(selected()).toEqual([true, false, false]);
      await user.keyboard("{ArrowDown}{ArrowDown}");
      expect(selected()).toEqual([false, false, true]);
      expect(screen.getAllByRole("option")[2]).toHaveTextContent("Lihat semua hasil (2)");
      expect(box).toHaveAttribute("aria-activedescendant", screen.getAllByRole("option")[2]!.id);
      await user.keyboard("{ArrowDown}");
      expect(selected()).toEqual([true, false, false]);
      await user.keyboard("{ArrowUp}");
      expect(selected()).toEqual([false, false, true]);
      await user.keyboard("{Enter}");
      await waitFor(() => expect(router.state.location.search).toBe("?q=us"));
      expect(router.state.location.pathname).toBe("/users");
    });

    it("ArrowUp from no selection lands on 'see all', then walks up and wraps from the first", async () => {
      const { user, box } = await openHome();
      await user.type(box, "us");
      await screen.findAllByRole("option");
      await user.keyboard("{ArrowUp}");
      expect(selected()).toEqual([false, false, true]);
      await user.keyboard("{ArrowUp}");
      expect(selected()).toEqual([false, true, false]);
      await user.keyboard("{ArrowUp}");
      expect(selected()).toEqual([true, false, false]);
      await user.keyboard("{ArrowUp}");
      expect(selected()).toEqual([false, false, true]);
    });

    it("reopens a closed list but selects nothing when there are no options", async () => {
      answerWith([]);
      const { user, box } = await openHome();
      await user.type(box, "zz");
      await screen.findByText("Gak ada email yang cocok sama “zz”");
      await user.keyboard("{Escape}");
      expect(screen.queryByRole("listbox")).toBeNull();
      await user.keyboard("{ArrowDown}");
      expect(screen.getByRole("listbox")).toBeInTheDocument();
      expect(box).not.toHaveAttribute("aria-activedescendant");
    });
  });

  describe("Escape", () => {
    it("first closes the list and keeps the text, the second clears the field", async () => {
      const { user, box } = await openHome();
      await user.type(box, "us");
      await screen.findAllByRole("option");
      await user.keyboard("{Escape}");
      expect(screen.queryByRole("listbox")).toBeNull();
      expect(box).toHaveValue("us");
      expect(box).toHaveFocus();
      await user.keyboard("{Escape}");
      expect(box).toHaveValue("");
      expect(screen.queryByRole("listbox")).toBeNull();
    });

    it("an Escape after ArrowDown reopened the list only closes it again", async () => {
      const { user, box } = await openHome();
      await user.type(box, "us");
      await screen.findAllByRole("option");
      await user.keyboard("{Escape}{ArrowDown}{Escape}");
      // ArrowDown reopened the list, so this Escape only closed it again.
      expect(box).toHaveValue("us");
      await user.keyboard("{Escape}");
      expect(box).toHaveValue("");
    });
  });
});
