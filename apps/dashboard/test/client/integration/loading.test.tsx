import { screen, within } from "@testing-library/react";
import { delay, http } from "msw";
import { afterEach, describe, expect, it, vi } from "vitest";
import { API } from "../helpers/handlers";
import { renderApp } from "../helpers/render";
import { server } from "../setup";

// Design component 2, State: while loading, the real frame (titles, labels, column headers) stays and
// only the values are sand blocks inside an aria-busy container.
const hang = (path: string) => server.use(http.get(`${API}${path}`, () => delay("infinite")));

const phone = () =>
  vi.spyOn(window, "matchMedia").mockImplementation(
    (query) =>
      ({
        matches: query === "(max-width: 767px)",
        media: query,
        addEventListener: () => {},
        removeEventListener: () => {},
      }) as unknown as MediaQueryList,
  );

afterEach(() => vi.restoreAllMocks());

describe("loading skeletons", () => {
  it("Users: the table frame with its headers, busy", async () => {
    hang("/users");
    renderApp("/users");
    const busy = await screen.findByLabelText("Lagi muat daftar user");
    expect(busy).toHaveAttribute("aria-busy", "true");
    for (const name of [
      "User",
      "Daftar",
      "Terakhir aktif",
      "File",
      "Data sync",
      "Key AI",
      "Status",
    ]) {
      expect(
        within(busy).getByRole("columnheader", { name: new RegExp(`^${name}`) }),
      ).toBeInTheDocument();
    }
    expect(within(busy).getByRole("columnheader", { name: /^Daftar/ })).toHaveAttribute(
      "aria-sort",
      "descending",
    );
  });

  it("Users on a phone: card rows with the real labels, not the wide table", async () => {
    phone();
    hang("/users");
    renderApp("/users");
    const busy = await screen.findByLabelText("Lagi muat daftar user");
    expect(within(busy).queryByRole("table")).toBeNull();
    expect(within(busy).getAllByText("Terakhir aktif")).toHaveLength(8);
  });

  it("Invites: the table frame and filter tabs without counts yet", async () => {
    hang("/invites");
    renderApp("/invites");
    const busy = await screen.findByLabelText("Lagi muat kode undangan");
    for (const name of ["Kode", "Status", "Dipakai oleh", "Tanggal dipakai", "Aksi"]) {
      expect(within(busy).getByRole("columnheader", { name })).toBeInTheDocument();
    }
    // Real labels, no misleading "0" while the list loads.
    expect(screen.getAllByRole("tab", { name: "Semua" })[0]!).toBeInTheDocument();
    expect(screen.getAllByRole("tab", { name: "Belum dipakai" })[0]!).toBeInTheDocument();
  });

  it("User detail: card titles and fact labels stay, values pulse", async () => {
    hang("/users/:id");
    renderApp("/users/u1");
    const busy = await screen.findByLabelText("Lagi muat user");
    expect(busy).toHaveAttribute("aria-busy", "true");
    for (const label of [
      "Daftar",
      "Terakhir aktif",
      "Masuk lewat",
      "Kode undangan",
      "File buku",
      "Data sync",
      "Kuota AI gratis",
    ]) {
      expect(within(busy).getByText(label)).toBeInTheDocument();
    }
    expect(within(busy).getByRole("heading", { name: "Perangkat" })).toBeInTheDocument();
    for (const b of within(busy).getAllByRole("button", { name: "Salin email" }))
      expect(b).toBeDisabled();
  });
});
