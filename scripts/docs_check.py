#!/usr/bin/env python3
"""Check that docs keep their structure and that citations to them resolve.

Docs (`docs/**/*.md`, rules in `.claude/rules/docs.md`):
- front matter with `type`, `purpose`, and `sections`; the `##` headings match
  `sections` exactly, in order;
- headings carry no issue numbers, dates, or history markers;
- at most MAX_LINES lines; listed in `docs/README.md`;
- relative links point at files that exist, and `#anchors` at real headings;
- every image under `docs/images/` is referenced somewhere.

Citations: comments citing `docs/<file>.md` or `docs/<file>.md, <Section>` in
app code, tests, and Wrangler configs name an existing file and, when a section
is given, a heading that contains it. Markdown files outside `docs/` (CLAUDE.md,
.claude rules and skills, READMEs) only need to name existing docs.

Exit 1 on any problem. Run from the repo root: `make docs-check`.
Pass file paths to check only those docs (citations are always checked).
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
MAX_LINES = 400
TYPES = {"reference", "explanation", "how-to", "index"}
CODE_DIRS = [
    "apps/mobile/lib",
    "apps/mobile/test",
    "apps/backend/src",
    "apps/backend/test",
    "apps/dashboard/worker",
    "apps/dashboard/client",
    "apps/dashboard/test",
    "apps/dashboard/e2e",
]
CODE_SUFFIXES = {".dart", ".ts", ".tsx", ".jsonc"}
SKIP = (".g.dart", ".freezed.dart")
PROSE = ["CLAUDE.md", "README.md", "apps", ".claude"]
CITE = re.compile(r"(docs/[\w/.-]+\.md)(?:,\s*([^)\n]+))?")
LINK = re.compile(r"\]\(([^)\s]+?\.md)?(#[^)\s]*)?\)")
IMAGE = re.compile(r"images/[\w.-]+\.(?:png|jpe?g|gif|svg|webp)")
BAD_HEADING = re.compile(
    r"#\d+|\b20\d\d\b|\b(?:history|historical|changelog|todo|deprecated|legacy|old)\b",
    re.IGNORECASE,
)

errors: list[str] = []
headings: dict[pathlib.Path, list[str]] = {}


def rel(path: pathlib.Path) -> str:
    return str(path.relative_to(ROOT))


def heads(path: pathlib.Path) -> list[str]:
    if path not in headings:
        headings[path] = [
            line.lstrip("#").strip()
            for line in path.read_text().splitlines()
            if line.startswith("#")
        ]
    return headings[path]


def slug(heading: str) -> str:
    # GitHub anchor: lowercase, drop punctuation except - and _, spaces → -.
    s = re.sub(r"[`*_~]", "", heading.lower())
    s = re.sub(r"[^\w\- ]", "", s)
    return s.replace(" ", "-")


def front_matter(path: pathlib.Path, lines: list[str]) -> dict[str, str] | None:
    if not lines or lines[0] != "---":
        return None
    try:
        end = lines.index("---", 1)
    except ValueError:
        return None
    meta = {}
    for line in lines[1:end]:
        key, _, value = line.partition(":")
        meta[key.strip()] = value.split(" #")[0].strip()
    return meta


def check_doc(doc: pathlib.Path, index_text: str) -> None:
    name = rel(doc)
    text = doc.read_text()
    lines = text.splitlines()
    if len(lines) > MAX_LINES:
        errors.append(f"{name}: {len(lines)} lines, max {MAX_LINES}; split it")
    meta = front_matter(doc, lines)
    if meta is None:
        errors.append(f"{name}: missing front matter (type, purpose, sections)")
        return
    if meta.get("type") not in TYPES:
        errors.append(f"{name}: type must be one of {sorted(TYPES)}")
    if not meta.get("purpose"):
        errors.append(f"{name}: front matter needs a purpose")
    raw = meta.get("sections", "")
    if not (raw.startswith("[") and raw.endswith("]")):
        errors.append(f"{name}: sections must be a [list]")
        return
    sections = [s.strip() for s in raw[1:-1].split(",") if s.strip()]
    in_code = False
    found = []
    for n, line in enumerate(lines, 1):
        if line.startswith("```"):
            in_code = not in_code
        if in_code or not line.startswith("#"):
            continue
        if BAD_HEADING.search(line.lstrip("#")):
            errors.append(f"{name}:{n}: heading has an issue number, date, or history marker")
        if line.startswith("## "):
            found.append(line[3:].strip())
    if found != sections:
        errors.append(f"{name}: ## headings {found} don't match sections {sections}")
    if doc != DOCS / "README.md" and f"({doc.relative_to(DOCS)})" not in index_text:
        errors.append(f"{name}: not listed in docs/README.md")


def check_links(doc: pathlib.Path) -> None:
    for n, line in enumerate(doc.read_text().splitlines(), 1):
        for m in LINK.finditer(line):
            target, anchor = m.group(1), m.group(2)
            if target and target.startswith(("http://", "https://")):
                continue
            path = (doc.parent / target).resolve() if target else doc
            if target and not path.exists():
                errors.append(f"{rel(doc)}:{n}: broken link {target}")
                continue
            if anchor and path.suffix == ".md":
                if slug(anchor[1:]) not in {slug(h) for h in heads(path)}:
                    errors.append(f"{rel(doc)}:{n}: no heading for {target or ''}{anchor}")


def check_citation(where: str, doc_path: str, section: str | None) -> None:
    doc = ROOT / doc_path
    if not doc.exists():
        errors.append(f"{where}: missing {doc_path}")
        return
    if section and not section.startswith(("docs/", "#")):
        # A section cut off by line wrap is still a prefix of the heading.
        name = re.split(r"\)|\. ", section)[0].strip().rstrip(".").lower()
        if name and not any(name in h.lower() for h in heads(doc)):
            errors.append(f"{where}: no section '{name}' in {doc_path}")


def check_code_citations() -> None:
    for base in CODE_DIRS:
        for f in (ROOT / base).rglob("*"):
            if f.suffix not in CODE_SUFFIXES or f.name.endswith(SKIP) or "node_modules" in f.parts:
                continue
            for n, line in enumerate(f.read_text().splitlines(), 1):
                if "//" not in line:
                    continue
                for m in CITE.finditer(line.split("//", 1)[1]):
                    check_citation(f"{rel(f)}:{n}", m.group(1), m.group(2))
    for name in ("apps/backend/wrangler.jsonc", "apps/dashboard/wrangler.jsonc"):
        f = ROOT / name
        for n, line in enumerate(f.read_text().splitlines(), 1):
            if "//" in line:
                for m in CITE.finditer(line.split("//", 1)[1]):
                    check_citation(f"{name}:{n}", m.group(1), m.group(2))


def check_prose_citations() -> list[pathlib.Path]:
    files = []
    for entry in PROSE:
        path = ROOT / entry
        found = [path] if path.is_file() else path.rglob("*.md")
        files += [f for f in found if "node_modules" not in f.parts and DOCS not in f.parents]
    for f in files:
        for n, line in enumerate(f.read_text().splitlines(), 1):
            for m in CITE.finditer(line):
                if not (ROOT / m.group(1)).exists():
                    errors.append(f"{rel(f)}:{n}: missing {m.group(1)}")
    return files


def check_images(markdown: list[pathlib.Path]) -> None:
    used = set()
    for f in markdown:
        used.update(IMAGE.findall(f.read_text()))
    for image in (DOCS / "images").glob("*"):
        if f"images/{image.name}" not in used:
            errors.append(f"{rel(image)}: not referenced by any doc or README")


HOOK = sys.argv[1:] == ["--hook"]
if HOOK:
    # PostToolUse hook: check the edited doc only; exit 2 shows errors to the agent.
    import json

    edited = json.load(sys.stdin).get("tool_input", {}).get("file_path", "")
    if not pathlib.Path(edited).resolve().is_relative_to(DOCS):
        sys.exit(0)
    sys.argv[1:] = [edited]
only = [pathlib.Path(p) if pathlib.Path(p).is_absolute() else ROOT / p for p in sys.argv[1:] if p.endswith(".md")]
docs = sorted(DOCS.rglob("*.md"))
index_text = (DOCS / "README.md").read_text()
for doc in docs:
    if only and doc.resolve() not in {p.resolve() for p in only}:
        continue
    check_doc(doc, index_text)
    check_links(doc)
check_code_citations()
prose = check_prose_citations()
if not only:
    check_links(ROOT / "README.md")
    check_images(docs + prose)

if HOOK:
    if errors:
        print("docs-check failed (see .claude/rules/docs.md):\n" + "\n".join(errors), file=sys.stderr)
    sys.exit(2 if errors else 0)
print("\n".join(errors) or "docs-check: ok")
sys.exit(1 if errors else 0)
