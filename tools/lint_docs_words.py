#!/usr/bin/env python3
"""Fail if repo Markdown docs exceed the word limit (see AGENTS.md)."""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MAX_WORDS = 500
DOC_GLOBS = ("*.md", "docs/**/*.md")


def iter_docs() -> list[Path]:
    seen: set[Path] = set()
    docs: list[Path] = []
    for pattern in DOC_GLOBS:
        for path in ROOT.glob(pattern):
            if not path.is_file():
                continue
            resolved = path.resolve()
            if resolved in seen:
                continue
            seen.add(resolved)
            docs.append(path.relative_to(ROOT))
    return sorted(docs)


def word_count(text: str) -> int:
    # Strip fenced code so architecture trees / command blocks don't dominate.
    without_fences = re.sub(r"```.*?```", " ", text, flags=re.DOTALL)
    return len(re.findall(r"\S+", without_fences))


def main() -> int:
    failures: list[str] = []
    rows: list[tuple[str, int]] = []
    for rel in iter_docs():
        count = word_count((ROOT / rel).read_text(encoding="utf-8"))
        rows.append((str(rel), count))
        if count > MAX_WORDS:
            failures.append(f"{rel}: {count} words (max {MAX_WORDS})")

    width = max(len(path) for path, _ in rows) if rows else 0
    for path, count in rows:
        mark = "FAIL" if count > MAX_WORDS else "ok"
        print(f"{path:<{width}}  {count:>4}  {mark}")

    if failures:
        print("\nDocs word-limit failures:", file=sys.stderr)
        for line in failures:
            print(f"  {line}", file=sys.stderr)
        print(
            f"\nEvery Markdown doc under / and docs/ must be ≤ {MAX_WORDS} words "
            "(fenced code excluded). Trim prose; keep IDs.",
            file=sys.stderr,
        )
        return 1

    print(f"\nAll {len(rows)} docs ≤ {MAX_WORDS} words.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
