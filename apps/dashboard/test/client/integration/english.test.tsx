import { screen, within } from "@testing-library/react";
import { beforeEach, describe, expect, it } from "vitest";
import { loadLang } from "../../../client/i18n";
import { useUiStore } from "../../../client/stores/ui-store";
import { renderApp } from "../helpers/render";

// The other integration tests pin Indonesian; this walks every screen in English to catch copy
// that skipped the dictionaries and formatting that ignored the locale.
describe("English UI", () => {
  beforeEach(async () => {
    await loadLang("en");
    useUiStore.setState({ lang: "en" });
  });

  it("Overview: English labels and English number formats", async () => {
    renderApp("/");
    expect(await screen.findByRole("heading", { name: "Overview", level: 1 })).toBeInTheDocument();
    expect(await screen.findByText("12,480")).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Registered users" })).toHaveTextContent("48");
    expect(screen.getByText("of 48 users")).toBeInTheDocument();
    expect(screen.getByText(/rows today · 87,520 left/)).toBeInTheDocument();
    expect(screen.getByText("12% used")).toBeInTheDocument();
    expect(screen.getByText(/of \$5/)).toBeInTheDocument();
    const services = screen.getByRole("heading", { name: "Services" }).closest("section")!;
    expect(within(services).getAllByText("On")).toHaveLength(2);
    expect(within(services).getByText("Off")).toBeInTheDocument();
    expect(await screen.findByRole("table", { name: "Newest users" })).toBeInTheDocument();
    expect(screen.getAllByRole("columnheader", { name: "Joined" }).length).toBeGreaterThan(0);
  });

  it("Users: list, summary, and column headers", async () => {
    renderApp("/users");
    expect(await screen.findByRole("heading", { name: "Users", level: 1 })).toBeInTheDocument();
    expect(await screen.findByText("48 users · 1 banned")).toBeInTheDocument();
    expect(screen.getAllByRole("combobox", { name: "Activity" })[0]).toBeInTheDocument();
    expect(await screen.findByRole("table", { name: "User list" })).toBeInTheDocument();
    expect(screen.getByRole("columnheader", { name: /Last active/ })).toBeInTheDocument();
    expect(screen.getAllByText("Never").length).toBeGreaterThan(0);
  });

  it("User detail: profile, AI quota, devices, ban dialog", async () => {
    const { user } = renderApp("/users/u1");
    expect(await screen.findByRole("heading", { name: /^sekar\.ayu\s?@gmail\.com$/ })).toBeInTheDocument();
    expect(screen.getByText("Signs in with")).toBeInTheDocument();
    expect(screen.getByText("Luma app 0.3.0")).toBeInTheDocument();
    expect(screen.getByText("1 session, including expired ones")).toBeInTheDocument();
    expect(screen.getByText(/key valid until Dec 14, 2026/)).toBeInTheDocument();
    await user.click(screen.getByRole("button", { name: "Ban user" }));
    const dialog = await screen.findByRole("dialog");
    expect(within(dialog).getByRole("heading", { name: "Ban this user?" })).toBeInTheDocument();
    expect(within(dialog).getByText("Sign-in, backup, and sync keep working")).toBeInTheDocument();
    expect(within(dialog).getByText("to cancel")).toBeInTheDocument();
  });

  it("Invites: filters, statuses, and actions", async () => {
    renderApp("/invites");
    expect(await screen.findByRole("heading", { name: "Invites", level: 1 })).toBeInTheDocument();
    expect(await screen.findByRole("tab", { name: /All\s*3/ })).toHaveAttribute("aria-selected", "true");
    expect(screen.getByRole("tab", { name: /Unused\s*2/ })).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Copy LUMA-AAAAA-BBBBB" })).toBeInTheDocument();
    expect(screen.getByText("1–3 of 3")).toBeInTheDocument();
  });
});
