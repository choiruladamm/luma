#!/usr/bin/env python3
"""Check that doc citations still resolve.

- Code comments citing `docs/<file>.md` or `docs/<file>.md, <Section>` in
  apps/mobile/lib and apps/backend/src: the file exists and, when a section is
  named, some heading in that file contains it.
- Relative Markdown links between docs (`[x](other.md)`) point at files that exist.

Exit 1 on any broken reference. Run from the repo root: `make docs-check`.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CODE_DIRS = [ROOT / "apps/mobile/lib", ROOT / "apps/backend/src"]
SKIP = (".g.dart", ".freezed.dart")
CITE = re.compile(r"(docs/[\w/.-]+\.md)(?:,\s*([^)\n]+))?")
LINK = re.compile(r"\]\(([^)#\s]+\.md)(?:#[^)]*)?\)")

headings: dict[pathlib.Path, list[str]] = {}


def heads(path: pathlib.Path) -> list[str]:
    if path not in headings:
        headings[path] = [
            line.lower() for line in path.read_text().splitlines() if line.startswith("#")
        ]
    return headings[path]


errors = []

for base in CODE_DIRS:
    for f in base.rglob("*"):
        if f.suffix not in (".dart", ".ts") or f.name.endswith(SKIP):
            continue
        for n, line in enumerate(f.read_text().splitlines(), 1):
            if "//" not in line:
                continue
            for m in CITE.finditer(line.split("//", 1)[1]):
                doc, section = ROOT / m.group(1), m.group(2)
                where = f"{f.relative_to(ROOT)}:{n}"
                if not doc.exists():
                    errors.append(f"{where}: missing {m.group(1)}")
                    continue
                if section and not section.startswith(("docs/", "#")):
                    # A section cut off by line wrap is still a prefix of the heading.
                    name = re.split(r"\)|\. ", section)[0].strip().rstrip(".").lower()
                    if name and not any(name in h for h in heads(doc)):
                        errors.append(f"{where}: no section '{name}' in {m.group(1)}")

for doc in (ROOT / "docs").rglob("*.md"):
    for n, line in enumerate(doc.read_text().splitlines(), 1):
        for m in LINK.finditer(line):
            target = m.group(1)
            if target.startswith(("http://", "https://")):
                continue
            if not (doc.parent / target).resolve().exists():
                errors.append(f"{doc.relative_to(ROOT)}:{n}: broken link {target}")

print("\n".join(errors) or "docs-check: ok")
sys.exit(1 if errors else 0)
