#!/usr/bin/env python3
"""Flag code comments that break `.claude/rules/code-comments.md`.

Catches what a grep can: Indonesian words, history phrasing, and issue
numbers outside `TODO(#N)` or spike evidence. Comments that quote Indonesian UI
copy in double quotes are allowed.

Usage: `python3 scripts/comments_check.py [files...]` (no args: all app code).
`--hook` reads a Claude Code PostToolUse payload and checks the edited file;
exit 2 shows the problems to the agent.
"""

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DIRS = ["apps/backend/vitest.config.ts", "apps/backend/drizzle.config.ts",
        "apps/dashboard/vite.config.ts", "apps/dashboard/vitest.config.ts",
        "apps/dashboard/vitest.client.config.ts", "apps/dashboard/playwright.config.ts",
        "apps/mobile/lib", "apps/mobile/test", "apps/mobile/tool", "apps/backend/src",
        "apps/backend/test", "apps/backend/scripts", "apps/dashboard/worker",
        "apps/dashboard/client", "apps/dashboard/test", "apps/dashboard/e2e"]
SUFFIXES = {".dart", ".ts", ".tsx"}
SKIP = (".g.dart", ".freezed.dart", ".d.ts")
# A whole-line comment (`//`, `///`, `/*`, ` * `) or a trailing ` // ` after code.
COMMENT = re.compile(r"^\s*(?:///?|/\*\*?|\*(?!\*))\s?(.*)$|\s//\s?(.*)$")
INDONESIAN = re.compile(
    r"\b(?:yang|gak|nggak|enggak|buat|kalau|kalo|udah|sudah|biar|supaya|karena|"
    r"soalnya|dulu|sekarang|tetep|tetap|abis|tiap|dipake|dipakai|dengan|untuk|"
    r"belum|lagi|bisa|harus|juga|cuma|aja|dong|nih|kita|jadi|terus|pas|ini|itu|atau|dan|ada|"
    r"tidak|pakai|pake|masih|jangan|bikin|langsung|sama|dari|di|ke|ngga|kok|sih|gue|lo|"
    r"dibuang|disimpan|disimpen|diganti|dipanggil|ditutup|dibuka|kosong|baris|semua)\b",
    re.IGNORECASE,
)
HISTORY = re.compile(r"\b(?:changed from|used to|previously|was added|added for)\b", re.I)
ISSUE = re.compile(r"(?<![\w&])#\d+\b")  # not hex colors like #22201C
ALLOWED_ISSUE = re.compile(r"TODO\(#\d+\)|spike #\d+|\(#\d+\)|#\d+ (?:live )?evidence|eval #\d+")
# Eval harness files record which spike or evidence run they reproduce.
EVAL = re.compile(r"test/(?:support|data)/book_chat_")
QUOTED = re.compile(r'"[^"]*"|“[^”]*”')
# Product terms that are Indonesian UI names, used unquoted in English prose.
PRODUCT = re.compile(r"Nyambung ke|Di luar buku|Balik ke \w+|Tokoh & istilah|Cari kata|Cari buku|Lanjut baca")


def problems(path: pathlib.Path) -> list[str]:
    out = []
    if path.suffix not in SUFFIXES or path.name.endswith(SKIP) or "l10n" in path.parts:
        return out
    for n, line in enumerate(path.read_text(errors="ignore").splitlines(), 1):
        m = COMMENT.search(line)
        if not m:
            continue
        body = m.group(1) if m.group(1) is not None else m.group(2)
        text = PRODUCT.sub("", QUOTED.sub("", body))
        where = f"{path.relative_to(ROOT)}:{n}"
        if INDONESIAN.search(text):
            out.append(f"{where}: comment isn't English: {body.strip()[:70]}")
        elif HISTORY.search(text):
            out.append(f"{where}: comment narrates history (belongs in the commit)")
        elif ISSUE.search(ALLOWED_ISSUE.sub("", text)) and not EVAL.search(str(path)):
            out.append(f"{where}: issue number outside TODO(#N) or spike evidence")
    return out


if sys.argv[1:] == ["--hook"]:
    edited = pathlib.Path(json.load(sys.stdin).get("tool_input", {}).get("file_path", ""))
    found = problems(edited.resolve()) if edited.exists() and ROOT in edited.resolve().parents else []
    if found:
        print("comments-check (see .claude/rules/code-comments.md):\n" + "\n".join(found), file=sys.stderr)
    sys.exit(2 if found else 0)

args = [ROOT / a for a in sys.argv[1:]]
files = [f for a in args for f in ([a] if a.is_file() else a.rglob("*")) if "node_modules" not in f.parts] or [
    f for d in DIRS for f in ([ROOT / d] if (ROOT / d).is_file() else (ROOT / d).rglob("*"))
    if "node_modules" not in f.parts
]
found = [p for f in files if f.is_file() for p in problems(f)]
print("\n".join(found) or "comments-check: ok")
sys.exit(1 if found else 0)
