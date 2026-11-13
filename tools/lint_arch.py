#!/usr/bin/env python3
"""Enforce P3 modular architecture bars (RUB-P3-*). See docs/rubric.md."""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

SOFT_MAX_LINES = 400
SOFT_MAX_METHODS = 25
HARD_MAX_LINES = 650
HARD_MAX_METHODS = 45
MAX_SIZE_ALLOWLIST_ENTRIES = 5
REACH_IN_DEPTH = 3

ALLOWED_GD_PREFIXES = (
    "scripts/",
    "scenes/",
    "ui/",
    "autoload/",
    "tests/",
    "playtests/",
    "tools/",
    "addons/",
)

SIZE_ALLOWLIST_PATH = ROOT / "tools" / "arch_size_allowlist.txt"
AUTOLOAD_ALLOWLIST_PATH = ROOT / "tools" / "arch_autoload_allowlist.txt"
PROJECT_GODOT = ROOT / "project.godot"

FUNC_RE = re.compile(r"(?m)^(static\s+)?func\s+")
EXTENDS_RE = re.compile(r"(?m)^extends\s+(\w+)")
GET_NODE_RE = re.compile(
    r"""get_node\s*\(\s*(?:["']([^"']+)["']|([A-Za-z_][\w.]*))"""
)
DOLLAR_PATH_RE = re.compile(r"(?<![\w$])\$([A-Za-z_][\w/]*)")
PERCENT_RE = re.compile(r"(?<![\w%])%[A-Za-z_]\w*")
PLATFORM_API_RE = re.compile(
    r"\b(?:OS\.get_name|OS\.get_distribution_name|DisplayServer\.get_name)\s*\("
)
NODEISH_EXTENDS = frozenset(
    {
        "Node",
        "Node2D",
        "Node3D",
        "Control",
        "CanvasItem",
        "CanvasLayer",
        "Viewport",
        "Window",
        "AcceptDialog",
        "ConfirmationDialog",
        "FileDialog",
        "Popup",
        "PopupPanel",
        "PopupMenu",
        "TabContainer",
        "Panel",
        "PanelContainer",
        "Container",
        "BoxContainer",
        "HBoxContainer",
        "VBoxContainer",
        "GridContainer",
        "MarginContainer",
        "ScrollContainer",
        "SubViewport",
        "SubViewportContainer",
        "Camera2D",
        "Camera3D",
        "Sprite2D",
        "AnimatedSprite2D",
        "Label",
        "RichTextLabel",
        "Button",
        "TextureRect",
        "ColorRect",
        "ItemList",
        "Tree",
        "LineEdit",
        "TextEdit",
        "SpinBox",
        "Slider",
        "ProgressBar",
        "Timer",
        "AnimationPlayer",
        "AudioStreamPlayer",
        "AudioStreamPlayer2D",
        "CharacterBody2D",
        "RigidBody2D",
        "StaticBody2D",
        "Area2D",
        "CollisionShape2D",
        "TileMap",
        "TileMapLayer",
    }
)
RULES_OK_EXTENDS = frozenset({"RefCounted", "Object"})


def _strip_comments_and_strings(text: str) -> str:
    """Rough strip so string literals do not trigger reach-in / API scans."""
    out: list[str] = []
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        if ch == '"' and text[i : i + 3] == '"""':
            end = text.find('"""', i + 3)
            out.append(" ")
            i = n if end < 0 else end + 3
            continue
        if ch == "'" and text[i : i + 3] == "'''":
            end = text.find("'''", i + 3)
            out.append(" ")
            i = n if end < 0 else end + 3
            continue
        if ch in "\"'":
            quote = ch
            i += 1
            while i < n:
                if text[i] == "\\":
                    i += 2
                    continue
                if text[i] == quote:
                    i += 1
                    break
                i += 1
            out.append('""')
            continue
        if ch == "#":
            while i < n and text[i] != "\n":
                i += 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def _line_of(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


def _path_depth(node_path: str) -> int:
    cleaned = node_path.strip().strip("/")
    if not cleaned:
        return 0
    # Ignore leading '.' / '..' segments for depth of named nodes.
    parts = [p for p in cleaned.split("/") if p and p not in (".", "..")]
    return len(parts)


def parse_size_allowlist(text: str) -> dict[str, tuple[int, int]]:
    result: dict[str, tuple[int, int]] = {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = re.split(r"\s+", line)
        if len(parts) != 3:
            raise ValueError(f"bad size allowlist line: {raw!r}")
        path, max_lines, max_methods = parts
        result[path] = (int(max_lines), int(max_methods))
    return result


def load_size_allowlist() -> dict[str, tuple[int, int]]:
    if not SIZE_ALLOWLIST_PATH.is_file():
        return {}
    return parse_size_allowlist(SIZE_ALLOWLIST_PATH.read_text(encoding="utf-8"))


def load_size_allowlist_at_ref(base_ref: str) -> dict[str, tuple[int, int]] | None:
    """Baseline allowlist at base_ref, or None if unavailable."""
    rel = SIZE_ALLOWLIST_PATH.relative_to(ROOT).as_posix()
    try:
        out = subprocess.check_output(
            ["git", "show", f"{base_ref}:{rel}"],
            cwd=ROOT,
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    try:
        return parse_size_allowlist(out)
    except ValueError:
        return None


def check_size_allowlist_policy(
    failures: list[str],
    allowlist: dict[str, tuple[int, int]],
    base_ref: str,
) -> None:
    rel = SIZE_ALLOWLIST_PATH.relative_to(ROOT).as_posix()
    if len(allowlist) > MAX_SIZE_ALLOWLIST_ENTRIES:
        failures.append(
            f"{rel}:1: RUB-P3-01 size allowlist has {len(allowlist)} entries "
            f"(max {MAX_SIZE_ALLOWLIST_ENTRIES}); split oversized scripts "
            f"instead of growing the list"
        )
    baseline = load_size_allowlist_at_ref(base_ref)
    if baseline is None:
        return
    for path, (lines, methods) in allowlist.items():
        if path not in baseline:
            continue
        prev_lines, prev_methods = baseline[path]
        if lines > prev_lines or methods > prev_methods:
            failures.append(
                f"{rel}:1: RUB-P3-01 ratchet raised for {path} "
                f"({prev_lines}/{prev_methods} → {lines}/{methods}); "
                f"only shrink or remove — split the file instead"
            )


def load_autoload_allowlist() -> set[str]:
    names: set[str] = set()
    if not AUTOLOAD_ALLOWLIST_PATH.is_file():
        return names
    for raw in AUTOLOAD_ALLOWLIST_PATH.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        names.add(line.split()[0])
    return names


def parse_project_autoloads() -> list[tuple[str, int]]:
    """Return (name, line_no) for each [autoload] entry."""
    if not PROJECT_GODOT.is_file():
        return []
    text = PROJECT_GODOT.read_text(encoding="utf-8")
    lines = text.splitlines()
    in_section = False
    found: list[tuple[str, int]] = []
    for i, line in enumerate(lines, start=1):
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            in_section = stripped == "[autoload]"
            continue
        if not in_section or not stripped or stripped.startswith(";"):
            continue
        if "=" not in stripped:
            continue
        name = stripped.split("=", 1)[0].strip()
        if name:
            found.append((name, i))
    return found


def iter_script_gd() -> list[Path]:
    return sorted((ROOT / "scripts").rglob("*.gd"))


def check_layout(failures: list[str]) -> None:
    for path in ROOT.rglob("*.gd"):
        rel = path.relative_to(ROOT).as_posix()
        if any(rel.startswith(prefix) for prefix in ALLOWED_GD_PREFIXES):
            continue
        # Ignore editor/generated under .godot if present.
        if rel.startswith(".godot/"):
            continue
        failures.append(
            f"{rel}:1: RUB-P3-01 game .gd must live under "
            f"{', '.join(ALLOWED_GD_PREFIXES)}"
        )


def check_size(failures: list[str], allowlist: dict[str, tuple[int, int]]) -> None:
    for path in iter_script_gd():
        rel = path.relative_to(ROOT).as_posix()
        text = path.read_text(encoding="utf-8")
        lines = len(text.splitlines())
        methods = len(FUNC_RE.findall(text))
        max_lines, max_methods = allowlist.get(rel, (SOFT_MAX_LINES, SOFT_MAX_METHODS))

        if lines > HARD_MAX_LINES or methods > HARD_MAX_METHODS:
            failures.append(
                f"{rel}:1: RUB-P3-01 exceeds hard ceiling "
                f"({lines} lines / {methods} methods; max "
                f"{HARD_MAX_LINES}/{HARD_MAX_METHODS})"
            )
            continue

        if lines > max_lines or methods > max_methods:
            kind = "allowlist ratchet" if rel in allowlist else "soft max"
            failures.append(
                f"{rel}:1: RUB-P3-01 exceeds {kind} "
                f"({lines} lines / {methods} methods; max {max_lines}/{max_methods})"
            )


def check_reach_ins(failures: list[str]) -> None:
    for path in iter_script_gd():
        rel = path.relative_to(ROOT).as_posix()
        raw = path.read_text(encoding="utf-8")
        # Keep original for line numbers; scan a comment-stripped copy carefully.
        # For get_node string args we need the original string content.
        for match in GET_NODE_RE.finditer(raw):
            node_path = match.group(1)
            if node_path is None:
                continue  # NodePath variable — skip
            # Skip if this match sits inside a comment roughly.
            line_start = raw.rfind("\n", 0, match.start()) + 1
            prefix = raw[line_start : match.start()]
            if "#" in prefix:
                continue
            depth = _path_depth(node_path)
            if depth >= REACH_IN_DEPTH:
                line = _line_of(raw, match.start())
                failures.append(
                    f"{rel}:{line}: RUB-P3-02 deep get_node "
                    f"(depth {depth} ≥ {REACH_IN_DEPTH}): {node_path!r}"
                )

        scanned = _strip_comments_and_strings(raw)
        # Map indexes approximately by scanning original with same regex on raw
        # for $ paths — use raw but ignore comments via line prefix check.
        for match in DOLLAR_PATH_RE.finditer(raw):
            line_start = raw.rfind("\n", 0, match.start()) + 1
            prefix = raw[line_start : match.start()]
            if "#" in prefix:
                continue
            # Skip if inside a string (simple: odd quotes before on line).
            if prefix.count('"') % 2 == 1 or prefix.count("'") % 2 == 1:
                continue
            node_path = match.group(1)
            depth = _path_depth(node_path)
            if depth >= REACH_IN_DEPTH:
                line = _line_of(raw, match.start())
                failures.append(
                    f"{rel}:{line}: RUB-P3-02 deep $ reach-in "
                    f"(depth {depth} ≥ {REACH_IN_DEPTH}): ${node_path}"
                )
        _ = scanned  # reserved for future tighter scans


def check_autoloads(failures: list[str], allowlist: set[str]) -> None:
    for name, line in parse_project_autoloads():
        if name not in allowlist:
            failures.append(
                f"project.godot:{line}: RUB-P3-02 undeclared autoload {name!r} "
                f"(add to tools/arch_autoload_allowlist.txt only if cross-cutting)"
            )


def check_rules_purity(failures: list[str]) -> None:
    rules_dir = ROOT / "scripts" / "rules"
    if not rules_dir.is_dir():
        return
    for path in sorted(rules_dir.rglob("*.gd")):
        rel = path.relative_to(ROOT).as_posix()
        raw = path.read_text(encoding="utf-8")
        ext = EXTENDS_RE.search(raw)
        if not ext:
            failures.append(f"{rel}:1: RUB-P3-03 missing extends")
        else:
            base = ext.group(1)
            if base not in RULES_OK_EXTENDS:
                line = _line_of(raw, ext.start())
                failures.append(
                    f"{rel}:{line}: RUB-P3-03 rules must extend "
                    f"RefCounted/Object, not {base}"
                )
            if base in NODEISH_EXTENDS:
                line = _line_of(raw, ext.start())
                failures.append(
                    f"{rel}:{line}: RUB-P3-03 rules must not extend Node types"
                )

        for match in GET_NODE_RE.finditer(raw):
            line_start = raw.rfind("\n", 0, match.start()) + 1
            if "#" in raw[line_start : match.start()]:
                continue
            line = _line_of(raw, match.start())
            failures.append(f"{rel}:{line}: RUB-P3-03 rules must not call get_node")

        for match in DOLLAR_PATH_RE.finditer(raw):
            line_start = raw.rfind("\n", 0, match.start()) + 1
            prefix = raw[line_start : match.start()]
            if "#" in prefix or prefix.count('"') % 2 == 1 or prefix.count("'") % 2 == 1:
                continue
            line = _line_of(raw, match.start())
            failures.append(f"{rel}:{line}: RUB-P3-03 rules must not use $ node paths")

        for match in PERCENT_RE.finditer(raw):
            line_start = raw.rfind("\n", 0, match.start()) + 1
            prefix = raw[line_start : match.start()]
            if "#" in prefix or prefix.count('"') % 2 == 1 or prefix.count("'") % 2 == 1:
                continue
            name = match.group(0)[1:]  # drop '%'
            # Skip printf-style specs (%s, %d, %02d) and modulo leftovers.
            if len(name) <= 1 or name[0].islower():
                continue
            line = _line_of(raw, match.start())
            failures.append(
                f"{rel}:{line}: RUB-P3-03 rules must not use % unique node names"
            )


def check_platform(failures: list[str]) -> None:
    for path in iter_script_gd():
        rel = path.relative_to(ROOT).as_posix()
        if rel.startswith("scripts/platform/"):
            continue
        raw = path.read_text(encoding="utf-8")
        for match in PLATFORM_API_RE.finditer(raw):
            line_start = raw.rfind("\n", 0, match.start()) + 1
            if "#" in raw[line_start : match.start()]:
                continue
            line = _line_of(raw, match.start())
            failures.append(
                f"{rel}:{line}: RUB-P3-05 platform API must live under "
                f"scripts/platform/** ({match.group(0)})"
            )


def _git_changed_paths(base_ref: str) -> set[str]:
    cmds = [
        ["git", "diff", "--name-only", "--diff-filter=ACMR", f"{base_ref}...HEAD"],
        ["git", "diff", "--name-only", "--diff-filter=ACMR", base_ref],
    ]
    # Also include unstaged/staged local changes when comparing to base.
    local = ["git", "diff", "--name-only", "--diff-filter=ACMR", "HEAD"]
    paths: set[str] = set()
    for cmd in cmds:
        try:
            out = subprocess.check_output(cmd, cwd=ROOT, text=True, stderr=subprocess.DEVNULL)
        except subprocess.CalledProcessError:
            continue
        for line in out.splitlines():
            line = line.strip()
            if line:
                paths.add(line)
        if paths:
            break
    try:
        out = subprocess.check_output(local, cwd=ROOT, text=True, stderr=subprocess.DEVNULL)
        for line in out.splitlines():
            line = line.strip()
            if line:
                paths.add(line)
    except subprocess.CalledProcessError:
        pass
    return paths


def resolve_base_ref(cli_base: str | None) -> str:
    if cli_base:
        return cli_base
    env_base = os.environ.get("GITHUB_BASE_REF", "").strip()
    if env_base:
        return f"origin/{env_base}"
    return "origin/main"


def check_rules_tests_pairing(failures: list[str], base_ref: str) -> None:
    changed = _git_changed_paths(base_ref)
    if not changed:
        # First push / empty diff — nothing to pair.
        return
    rules_changed = any(
        p.startswith("scripts/rules/") and p.endswith(".gd") for p in changed
    )
    tests_changed = any(p.startswith("tests/") for p in changed)
    if rules_changed and not tests_changed:
        failures.append(
            f"scripts/rules/:1: RUB-P3-04 scripts/rules/** changed vs {base_ref} "
            "without any tests/** change"
        )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--require-rules-tests",
        action="store_true",
        default=os.environ.get("ARCH_LINT_RULES_DIFF", "") == "1",
        help="Fail if scripts/rules/** changes without tests/** (CI default).",
    )
    parser.add_argument(
        "--base-ref",
        default=None,
        help="Git ref for pairing diff (default: GITHUB_BASE_REF or origin/main).",
    )
    args = parser.parse_args(argv)

    failures: list[str] = []
    try:
        size_allowlist = load_size_allowlist()
        autoload_allowlist = load_autoload_allowlist()
    except ValueError as exc:
        print(f"Allowlist error: {exc}", file=sys.stderr)
        return 2

    base_ref = resolve_base_ref(args.base_ref)
    check_layout(failures)
    check_size_allowlist_policy(failures, size_allowlist, base_ref)
    check_size(failures, size_allowlist)
    check_reach_ins(failures)
    check_autoloads(failures, autoload_allowlist)
    check_rules_purity(failures)
    check_platform(failures)
    if args.require_rules_tests:
        check_rules_tests_pairing(failures, base_ref)

    if failures:
        print("Architecture lint failures:", file=sys.stderr)
        for line in sorted(failures):
            print(f"  {line}", file=sys.stderr)
        print(
            "\nSee docs/rubric.md P3 (RUB-P3-*) and docs/requirements.md REQ-P3-*.",
            file=sys.stderr,
        )
        return 1

    print("arch-lint OK (RUB-P3-01…05).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
