import { act, render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { createMemoryRouter, RouterProvider } from "react-router";
import { describe, expect, it, vi } from "vitest";
import { Avatar, avatarColor } from "../../../client/components/ui/avatar";
import { Button, IconButton } from "../../../client/components/ui/button";
import { Chip } from "../../../client/components/ui/chip";
import { columnHelper, DataTable } from "../../../client/components/ui/data-table";
import { Pagination, pageList } from "../../../client/components/ui/pagination";
import { ConfirmFooter, Dialog } from "../../../client/components/ui/dialog";
import { Segmented } from "../../../client/components/ui/segmented";
import { EmptyState, ErrorState } from "../../../client/components/ui/states";
import { ToastHost } from "../../../client/components/ui/toast-host";
import { Highlight } from "../../../client/components/ui/highlight";
import { Select } from "../../../client/components/ui/select";
import { toast } from "../../../client/stores/toast-store";

describe("Button / IconButton", () => {
  it("is a real button, disabled blocks clicks", async () => {
    const onClick = vi.fn<() => void>();
    render(
      <Button onClick={onClick} disabled>
        Bikin kode
      </Button>,
    );
    await userEvent.click(screen.getByRole("button", { name: "Bikin kode" }));
    expect(onClick).not.toHaveBeenCalled();
  });

  it("names icon-only buttons through aria-label", () => {
    render(<IconButton icon="refresh" label="Muat ulang data" />);
    expect(screen.getByRole("button", { name: "Muat ulang data" })).toBeInTheDocument();
  });
});

describe("Button loading", () => {
  // Hugeicons renders an <svg>; the spinner is the one with the spin class.
  const svgs = (el: HTMLElement) => [...el.querySelectorAll("svg")];

  it("swaps the icon for a spinner, keeps the label, and blocks clicks", async () => {
    const onClick = vi.fn<() => void>();
    render(
      <Button icon="plus" loading onClick={onClick}>
        Bikin kode
      </Button>,
    );
    const button = screen.getByRole("button", { name: "Bikin kode" });
    expect(button).toBeDisabled();
    expect(button).toHaveAttribute("aria-busy", "true");
    expect(svgs(button)).toHaveLength(1);
    expect(svgs(button)[0]).toHaveClass("motion-safe:animate-spin");
    await userEvent.click(button);
    expect(onClick).not.toHaveBeenCalled();
  });

  it("puts the spinner left of the label when there is no icon", () => {
    render(<Button loading>Muat lagi</Button>);
    const button = screen.getByRole("button", { name: "Muat lagi" });
    expect(button.firstElementChild?.tagName.toLowerCase()).toBe("svg");
    expect(button.firstElementChild).toHaveClass("motion-safe:animate-spin");
  });

  it("IconButton keeps its name and shows only the spinner", () => {
    render(<IconButton icon="refresh" label="Muat ulang data" loading />);
    const button = screen.getByRole("button", { name: "Muat ulang data" });
    expect(button).toBeDisabled();
    expect(svgs(button)).toHaveLength(1);
    expect(svgs(button)[0]).toHaveClass("motion-safe:animate-spin");
  });

  it("without loading it renders the icon, not busy", () => {
    render(<Button icon="plus">Bikin kode</Button>);
    const button = screen.getByRole("button", { name: "Bikin kode" });
    expect(button).not.toHaveAttribute("aria-busy");
    expect(svgs(button)[0]).not.toHaveClass("motion-safe:animate-spin");
  });
});

describe("Highlight", () => {
  it("marks the first case-insensitive match and keeps the text as typed", () => {
    const { container } = render(<Highlight text="Work.Adamm@gmail.com" q="adam" />);
    expect(container.textContent).toBe("Work.Adamm@gmail.com");
    expect(container.querySelector("mark")?.textContent).toBe("Adam");
  });

  it("renders plain text without a query or a match", () => {
    expect(render(<Highlight text="rara@luma.test" />).container.querySelector("mark")).toBeNull();
    expect(
      render(<Highlight text="rara@luma.test" q="zzz" />).container.querySelector("mark"),
    ).toBeNull();
  });
});

describe("Chip / Avatar", () => {
  it("always carries the status as text", () => {
    render(
      <Chip tone="danger" dot="filled">
        Di-ban
      </Chip>,
    );
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
    const onChange = vi.fn<() => void>();
    render(
      <Segmented
        label="Saring kode"
        value="all"
        onChange={onChange}
        options={[
          { value: "all", label: "Semua", count: 3 },
          { value: "used", label: "Udah dipakai", count: 1 },
        ]}
      />,
    );
    expect(screen.getByRole("tab", { name: /Semua/ })).toHaveAttribute("aria-selected", "true");
    await userEvent.click(screen.getByRole("tab", { name: /Udah dipakai/ }));
    expect(onChange).toHaveBeenCalledWith("used");
  });

  it("Tab enters at the selected option; arrows select and move focus, wrapping", async () => {
    const onChange = vi.fn<() => void>();
    render(
      <Segmented
        label="Saring kode"
        value="used"
        onChange={onChange}
        options={[
          { value: "all", label: "Semua" },
          { value: "unused", label: "Belum dipakai" },
          { value: "used", label: "Udah dipakai" },
        ]}
      />,
    );
    await userEvent.tab();
    expect(screen.getByRole("tab", { name: "Udah dipakai" })).toHaveFocus();
    await userEvent.keyboard("{ArrowRight}");
    expect(onChange).toHaveBeenLastCalledWith("all");
    expect(screen.getByRole("tab", { name: "Semua" })).toHaveFocus();
    await userEvent.keyboard("{End}");
    expect(onChange).toHaveBeenLastCalledWith("used");
  });

  it("uses radio semantics for settings", () => {
    render(
      <Segmented
        kind="radio"
        label="Tampilan"
        value="dark"
        onChange={() => {}}
        options={[
          { value: "light", label: "Terang" },
          { value: "dark", label: "Gelap" },
        ]}
      />,
    );
    expect(screen.getByRole("radio", { name: "Gelap" })).toHaveAttribute("aria-checked", "true");
  });
});

describe("Dialog", () => {
  it("renders title, description and footer when open; the close button calls onClose", async () => {
    const onClose = vi.fn<() => void>();
    render(
      <Dialog
        open
        onClose={onClose}
        title="Ban user ini?"
        description="Kuota AI gratisnya dicabut."
        icon="ban"
        footer={
          <ConfirmFooter>
            <Button>Batal</Button>
          </ConfirmFooter>
        }
      >
        isi
      </Dialog>,
    );
    expect(screen.getByRole("heading", { name: "Ban user ini?" })).toBeInTheDocument();
    expect(screen.getByText("Esc")).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Tutup dialog" }));
    expect(onClose).toHaveBeenCalled();
  });

  it("renders nothing inside while closed", () => {
    render(
      <Dialog open={false} onClose={() => {}} title="Ban user ini?" icon="ban" footer={null} />,
    );
    expect(screen.queryByRole("heading", { name: "Ban user ini?" })).toBeNull();
  });
});

describe("DataTable", () => {
  type Row = { id: string; email: string; bytes: number };
  const h = columnHelper<Row>();
  const columns = h.columns([
    h.accessor("email", { header: "User" }),
    h.accessor("bytes", { header: "File" }),
  ]);
  const data: Row[] = [{ id: "u1", email: "a@x.com", bytes: 5 }];

  it("renders headers, rows, and a link per row", () => {
    const router = createMemoryRouter([
      {
        path: "/",
        element: (
          <DataTable
            label="Daftar"
            columns={columns}
            data={data}
            rowHref={(r) => `/users/${r.id}`}
            numeric={["bytes"]}
            sort={{ id: "email", dir: "desc" }}
          />
        ),
      },
    ]);
    render(<RouterProvider router={router} />);
    const table = screen.getByRole("table", { name: "Daftar" });
    expect(within(table).getByRole("columnheader", { name: /User/ })).toHaveAttribute(
      "aria-sort",
      "descending",
    );
    expect(within(table).getByRole("link", { name: "a@x.com" })).toHaveAttribute(
      "href",
      "/users/u1",
    );
    expect(within(table).getByRole("cell", { name: "5" })).toHaveClass("text-right");
  });

  it("sortable headers are buttons that report the column; the sorted one carries aria-sort", async () => {
    const onSort = vi.fn<() => void>();
    const router = createMemoryRouter([
      {
        path: "/",
        element: (
          <DataTable
            label="Daftar"
            columns={columns}
            data={data}
            sort={{ id: "bytes", dir: "asc" }}
            sortable={["bytes"]}
            onSort={onSort}
          />
        ),
      },
    ]);
    render(<RouterProvider router={router} />);
    expect(screen.getByRole("columnheader", { name: /File/ })).toHaveAttribute(
      "aria-sort",
      "ascending",
    );
    expect(screen.queryByRole("button", { name: /User/ })).toBeNull();
    await userEvent.click(screen.getByRole("button", { name: /File/ }));
    expect(onSort).toHaveBeenCalledWith("bytes");
  });
});

describe("Select", () => {
  const options: [string, string][] = [
    ["", "Semua"],
    ["active", "Aktif"],
    ["banned", "Di-ban"],
  ];

  it("opens a listbox with the chosen option checked, picks with the mouse, and closes", async () => {
    const onChange = vi.fn<() => void>();
    render(<Select label="Status" value="" options={options} onChange={onChange} />);
    await userEvent.click(screen.getByRole("button", { name: "Status: Semua" }));
    expect(screen.getByRole("option", { name: "Semua" })).toHaveAttribute("aria-selected", "true");
    await userEvent.click(screen.getByRole("option", { name: "Di-ban" }));
    expect(onChange).toHaveBeenCalledWith("banned");
    expect(screen.queryByRole("listbox")).toBeNull();
  });

  it("works from the keyboard and Esc returns focus to the trigger", async () => {
    const onChange = vi.fn<() => void>();
    render(<Select label="Status" value="" options={options} onChange={onChange} />);
    const trigger = screen.getByRole("button", { name: "Status: Semua" });
    trigger.focus();
    await userEvent.keyboard("{ArrowDown}");
    const list = screen.getByRole("listbox", { name: "Status" });
    expect(list).toHaveFocus();
    expect(list).toHaveAttribute(
      "aria-activedescendant",
      screen.getByRole("option", { name: "Semua" }).id,
    );
    await userEvent.keyboard("{ArrowDown}{Enter}");
    expect(onChange).toHaveBeenCalledWith("active");
    await userEvent.click(trigger);
    await userEvent.keyboard("{Escape}");
    expect(screen.queryByRole("listbox")).toBeNull();
    expect(trigger).toHaveFocus();
  });
});

describe("Select hover", () => {
  it("moves the highlight under the mouse without taking keyboard focus", async () => {
    render(
      <Select
        label="Status"
        value=""
        options={[
          ["", "Semua"],
          ["banned", "Di-ban"],
        ]}
        onChange={vi.fn<() => void>()}
      />,
    );
    await userEvent.click(screen.getByRole("button", { name: "Status: Semua" }));
    const list = screen.getByRole("listbox", { name: "Status" });
    await userEvent.hover(screen.getByRole("option", { name: "Di-ban" }));
    expect(list).toHaveFocus();
    expect(list).toHaveAttribute(
      "aria-activedescendant",
      screen.getByRole("option", { name: "Di-ban" }).id,
    );
  });
});

describe("Pagination", () => {
  it("lists first, last, and a window around the current page", () => {
    expect(pageList(1, 5)).toEqual([1, 2, 3, 4, 5]);
    expect(pageList(5, 10)).toEqual([1, null, 4, 5, 6, null, 10]);
    expect(pageList(1, 10)).toEqual([1, 2, null, 10]);
    expect(pageList(10, 10)).toEqual([1, null, 9, 10]);
  });

  it("a new page glides to the table's top only when that top is off screen", async () => {
    const onPage = vi.fn<() => void>();
    const scroll = vi.fn<() => void>();
    const { container } = render(
      <section>
        <Pagination page={2} pageCount={3} total={45} pageSize={20} onPage={onPage} />
      </section>,
    );
    const section = container.querySelector("section")!;
    section.scrollIntoView = scroll;
    vi.spyOn(section, "getBoundingClientRect").mockReturnValue({ top: -400 } as DOMRect);
    await userEvent.click(screen.getByRole("button", { name: "Halaman 3" }));
    expect(onPage).toHaveBeenCalledWith(3);
    expect(scroll).toHaveBeenCalledWith({ behavior: "smooth", block: "start" });

    scroll.mockClear();
    vi.spyOn(section, "getBoundingClientRect").mockReturnValue({ top: 120 } as DOMRect);
    await userEvent.click(screen.getByRole("button", { name: "Halaman 1" }));
    expect(scroll).not.toHaveBeenCalled();
  });

  it("shows the range, marks the current page, and disables the ends", async () => {
    const onPage = vi.fn<() => void>();
    render(<Pagination page={1} pageCount={3} total={45} pageSize={20} onPage={onPage} />);
    expect(screen.getByText("1–20 dari 45")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Halaman 1" })).toHaveAttribute(
      "aria-current",
      "page",
    );
    expect(screen.getByRole("button", { name: "Halaman sebelumnya" })).toBeDisabled();
    await userEvent.click(screen.getByRole("button", { name: "Halaman berikutnya" }));
    expect(onPage).toHaveBeenCalledWith(2);
  });
});

describe("states", () => {
  it("ErrorState is an alert with a retry", async () => {
    const onRetry = vi.fn<() => void>();
    render(<ErrorState message="Server admin gak ngejawab." onRetry={onRetry} />);
    expect(screen.getByRole("alert")).toHaveTextContent("Data gagal dimuat");
    await userEvent.click(screen.getByRole("button", { name: "Coba lagi" }));
    expect(onRetry).toHaveBeenCalled();
  });

  it("EmptyState shows title, sentence, action", () => {
    render(
      <EmptyState icon="users" title="Belum ada user" action={<Button>Ke Undangan</Button>}>
        Selama beta…
      </EmptyState>,
    );
    expect(screen.getByRole("heading", { name: "Belum ada user" })).toBeInTheDocument();
  });
});

describe("ToastHost", () => {
  it("auto-hides success after 2.5s, keeps errors until closed, runs actions", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    render(<ToastHost />);
    act(() => {
      toast("Kode disalin");
    });
    expect(screen.getByRole("status")).toHaveTextContent("Kode disalin");
    act(() => {
      vi.advanceTimersByTime(2600);
    });
    expect(screen.queryByText("Kode disalin")).toBeNull();

    act(() => {
      toast("Gagal nyalin kode. Coba lagi.", { tone: "error" });
    });
    act(() => {
      vi.advanceTimersByTime(10_000);
    });
    expect(screen.getByRole("alert")).toHaveTextContent("Gagal nyalin");
    await userEvent.click(screen.getByRole("button", { name: "Tutup" }));
    expect(screen.queryByRole("alert")).toBeNull();

    const onClick = vi.fn<() => void>();
    act(() => {
      toast("a@x.com di-ban", { action: { label: "Buka ban", onClick } });
    });
    await userEvent.click(screen.getByRole("button", { name: "Buka ban" }));
    expect(onClick).toHaveBeenCalled();
    vi.useRealTimers();
  });
});
