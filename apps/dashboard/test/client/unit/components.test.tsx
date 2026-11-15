import { act, render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { createMemoryRouter, RouterProvider } from "react-router";
import { describe, expect, it, vi } from "vitest";
import { Avatar, avatarColor } from "../../../client/components/ui/avatar";
import { Button, IconButton } from "../../../client/components/ui/button";
import { Chip } from "../../../client/components/ui/chip";
import { columnHelper, DataTable, LoadMore } from "../../../client/components/ui/data-table";
import { ConfirmFooter, Dialog } from "../../../client/components/ui/dialog";
import { Segmented } from "../../../client/components/ui/segmented";
import { EmptyState, ErrorState } from "../../../client/components/ui/states";
import { ToastHost } from "../../../client/components/ui/toast-host";
import { toast } from "../../../client/stores/toast-store";

describe("Button / IconButton", () => {
  it("is a real button, disabled blocks clicks", async () => {
    const onClick = vi.fn();
    render(<Button onClick={onClick} disabled>Bikin kode</Button>);
    await userEvent.click(screen.getByRole("button", { name: "Bikin kode" }));
    expect(onClick).not.toHaveBeenCalled();
  });

  it("names icon-only buttons through aria-label", () => {
    render(<IconButton icon="refresh" label="Muat ulang data" />);
    expect(screen.getByRole("button", { name: "Muat ulang data" })).toBeInTheDocument();
  });
});

describe("Chip / Avatar", () => {
  it("always carries the status as text", () => {
    render(<Chip tone="danger" dot="filled">Di-ban</Chip>);
    expect(screen.getByText("Di-ban")).toBeInTheDocument();
  });

  it("keeps the same color for the same email and hides the initial from screen readers", () => {
    expect(avatarColor("a@x.com")).toBe(avatarColor("a@x.com"));
    const { container } = render(<Avatar seed="a@x.com" label="ayu" />);
    expect(container.firstChild).toHaveAttribute("aria-hidden", "true");
    expect(container.textContent).toBe("a");
  });
});

describe("Segmented", () => {
  it("marks the active tab and reports changes", async () => {
    const onChange = vi.fn();
    render(<Segmented label="Saring kode" value="all" onChange={onChange} options={[{ value: "all", label: "Semua", count: 3 }, { value: "used", label: "Udah dipakai", count: 1 }]} />);
    expect(screen.getByRole("tab", { name: /Semua/ })).toHaveAttribute("aria-selected", "true");
    await userEvent.click(screen.getByRole("tab", { name: /Udah dipakai/ }));
    expect(onChange).toHaveBeenCalledWith("used");
  });

  it("uses radio semantics for settings", () => {
    render(<Segmented kind="radio" label="Tampilan" value="dark" onChange={() => {}} options={[{ value: "light", label: "Terang" }, { value: "dark", label: "Gelap" }]} />);
    expect(screen.getByRole("radio", { name: "Gelap" })).toHaveAttribute("aria-checked", "true");
  });
});

describe("Dialog", () => {
  it("renders title, description and footer when open; the close button calls onClose", async () => {
    const onClose = vi.fn();
    render(
      <Dialog open onClose={onClose} title="Ban user ini?" description="Kuota AI gratisnya dicabut." icon="ban" footer={<ConfirmFooter><Button>Batal</Button></ConfirmFooter>}>
        isi
      </Dialog>,
    );
    expect(screen.getByRole("heading", { name: "Ban user ini?" })).toBeInTheDocument();
    expect(screen.getByText("Esc")).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Tutup dialog" }));
    expect(onClose).toHaveBeenCalled();
  });

  it("renders nothing inside while closed", () => {
    render(<Dialog open={false} onClose={() => {}} title="Ban user ini?" icon="ban" footer={null} />);
    expect(screen.queryByRole("heading", { name: "Ban user ini?" })).toBeNull();
  });
});

describe("DataTable", () => {
  type Row = { id: string; email: string; bytes: number };
  const h = columnHelper<Row>();
  const columns = h.columns([h.accessor("email", { header: "User" }), h.accessor("bytes", { header: "File" })]);
  const data: Row[] = [{ id: "u1", email: "a@x.com", bytes: 5 }];

  it("renders headers, rows, and a link per row", () => {
    const router = createMemoryRouter([{ path: "/", element: <DataTable label="Daftar" columns={columns} data={data} rowHref={(r) => `/users/${r.id}`} numeric={["bytes"]} sortedBy="email" /> }]);
    render(<RouterProvider router={router} />);
    const table = screen.getByRole("table", { name: "Daftar" });
    expect(within(table).getByRole("columnheader", { name: /User/ })).toHaveAttribute("aria-sort", "descending");
    expect(within(table).getByRole("link", { name: "a@x.com" })).toHaveAttribute("href", "/users/u1");
    expect(within(table).getByRole("cell", { name: "5" })).toHaveClass("text-right");
  });

  it("LoadMore shows counts and only offers more when there is more", async () => {
    const onMore = vi.fn();
    const { rerender } = render(<LoadMore shown={10} total={48} onMore={onMore} />);
    expect(screen.getByText("Nampilin 10 dari 48")).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Muat lagi" }));
    expect(onMore).toHaveBeenCalled();
    rerender(<LoadMore shown={48} total={48} />);
    expect(screen.queryByRole("button", { name: "Muat lagi" })).toBeNull();
  });
});

describe("states", () => {
  it("ErrorState is an alert with a retry", async () => {
    const onRetry = vi.fn();
    render(<ErrorState message="Server admin gak ngejawab." onRetry={onRetry} />);
    expect(screen.getByRole("alert")).toHaveTextContent("Data gagal dimuat");
    await userEvent.click(screen.getByRole("button", { name: "Coba lagi" }));
    expect(onRetry).toHaveBeenCalled();
  });

  it("EmptyState shows title, sentence, action", () => {
    render(<EmptyState icon="users" title="Belum ada user" action={<Button>Ke Undangan</Button>}>Selama beta…</EmptyState>);
    expect(screen.getByRole("heading", { name: "Belum ada user" })).toBeInTheDocument();
  });
});

describe("ToastHost", () => {
  it("auto-hides success after 2.5s, keeps errors until closed, runs actions", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    render(<ToastHost />);
    act(() => toast("Kode disalin"));
    expect(screen.getByRole("status")).toHaveTextContent("Kode disalin");
    act(() => vi.advanceTimersByTime(2600));
    expect(screen.queryByText("Kode disalin")).toBeNull();

    act(() => toast("Gagal nyalin kode. Coba lagi.", { tone: "error" }));
    act(() => vi.advanceTimersByTime(10_000));
    expect(screen.getByRole("alert")).toHaveTextContent("Gagal nyalin");
    await userEvent.click(screen.getByRole("button", { name: "Tutup" }));
    expect(screen.queryByRole("alert")).toBeNull();

    const onClick = vi.fn();
    act(() => toast("a@x.com di-ban", { action: { label: "Buka ban", onClick } }));
    await userEvent.click(screen.getByRole("button", { name: "Buka ban" }));
    expect(onClick).toHaveBeenCalled();
    vi.useRealTimers();
  });
});
