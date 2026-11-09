#!/usr/bin/env python3
"""Select tier-1 test suites from git changes via tests/impact_map.toml.

Strict: any in-scope changed path that matches no rule fails.
Print suite paths (or ALL) for gd-tools / GitHub Actions.
"""

from __future__ import annotations

import argparse
import fnmatch
import os
import subprocess
import sys
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:  # Python < 3.11
    import tomli as tomllib  # type: ignore

ROOT = Path(__file__).resolve().parents[1]
MAP_PATH = ROOT / "tests" / "impact_map.toml"
IN_SCOPE_PREFIXES = (
    "scenes/",
    "scripts/",
    "ui/",
    "autoload/",
    "tests/",
    "addons/",
)
IN_SCOPE_FILES = {
    "project.godot",
    "icon.svg",
    "gd-tools.toml",
}


def load_map(path: Path = MAP_PATH) -> dict:
    data = tomllib.loads(path.read_text(encoding="utf-8"))
    domains = data.get("domains") or {}
    rules = data.get("rules") or []
    if not isinstance(domains, dict) or not isinstance(rules, list):
        raise SystemExit(f"{path}: invalid domains/rules shape")
    return {"domains": domains, "rules": rules}


def _git_diff_names(base_ref: str) -> list[str]:
    """Changed paths vs merge-base(base_ref, HEAD), plus working-tree dirt."""
    cmds = [
        ["git", "diff", "--name-only", "--diff-filter=ACMR", f"{base_ref}...HEAD"],
        ["git", "diff", "--name-only", "--diff-filter=ACMR", "HEAD"],
        ["git", "ls-files", "--others", "--exclude-standard"],
    ]
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
    return sorted(paths)


def in_scope(path: str) -> bool:
    if path in IN_SCOPE_FILES:
        return True
    if path == "tools/select_impacted_tests.py":
        return True
    return any(path.startswith(prefix) for prefix in IN_SCOPE_PREFIXES)


def match_rule(path: str, rule: dict) -> bool:
    pattern = rule.get("match")
    if not isinstance(pattern, str) or not pattern:
        return False
    return fnmatch.fnmatchcase(path, pattern)


def resolve_path(path: str, mapping: dict) -> tuple[str, set[str] | None]:
    """Return ('full', None) | ('domain', suites) | ('unmapped', None)."""
    domains: dict = mapping["domains"]
    for rule in mapping["rules"]:
        if not match_rule(path, rule):
            continue
        if rule.get("full"):
            return "full", None
        domain = rule.get("domain")
        if not isinstance(domain, str) or domain not in domains:
            return "unmapped", None
        suites = domains[domain].get("suites") or []
        return "domain", {f"tests/{name}" for name in suites}
    # Direct suite path always selects itself when present on disk.
    if path.startswith("tests/test_") and path.endswith(".gd"):
        if (ROOT / path).is_file():
            return "domain", {path}
    return "unmapped", None


def select(paths: list[str], mapping: dict) -> tuple[bool, list[str], list[str]]:
    """Return (full_run, suite_paths, unmapped)."""
    scoped = [p for p in paths if in_scope(p)]
    if not scoped:
        return False, [], []
    suites: set[str] = set()
    unmapped: list[str] = []
    full = False
    for path in scoped:
        kind, found = resolve_path(path, mapping)
        if kind == "full":
            full = True
        elif kind == "domain" and found is not None:
            suites.update(found)
        else:
            unmapped.append(path)
    if unmapped:
        return False, [], unmapped
    if full:
        return True, [], []
    return False, sorted(suites), []


def iter_production_gd() -> list[str]:
    files: list[str] = []
    for base in ("scripts", "scenes", "ui", "autoload", "tests"):
        root = ROOT / base
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*.gd")):
            files.append(path.relative_to(ROOT).as_posix())
    for name in IN_SCOPE_FILES:
        if (ROOT / name).exists():
            files.append(name)
    return files


def check_complete(mapping: dict) -> list[str]:
    missing: list[str] = []
    for path in iter_production_gd():
        kind, _ = resolve_path(path, mapping)
        if kind == "unmapped":
            missing.append(path)
    # Every declared suite file must exist.
    for domain, body in mapping["domains"].items():
        for name in body.get("suites") or []:
            suite = ROOT / "tests" / name
            if not suite.is_file():
                missing.append(f"missing suite for domain {domain}: tests/{name}")
    return missing


def write_github_output(full: bool, suites: list[str]) -> None:
    gh_out = os.environ.get("GITHUB_OUTPUT")
    if not gh_out:
        return
    with open(gh_out, "a", encoding="utf-8") as handle:
        handle.write(f"full={'true' if full else 'false'}\n")
        handle.write("suites<<EOF\n")
        for suite in suites:
            handle.write(f"{suite}\n")
        handle.write("EOF\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--base",
        default="",
        help="Git ref for merge-base diff (default: origin/main or GITHUB_BASE_REF)",
    )
    parser.add_argument(
        "--map",
        type=Path,
        default=MAP_PATH,
        help="Path to impact_map.toml",
    )
    parser.add_argument(
        "--check-complete",
        action="store_true",
        help="Fail if any in-repo .gd path is unmapped",
    )
    parser.add_argument(
        "--github-output",
        action="store_true",
        help="Append full= / suites= to $GITHUB_OUTPUT",
    )
    parser.add_argument(
        "--print-command",
        action="store_true",
        help="Print a gd-tools test argument line",
    )
    parser.add_argument(
        "paths",
        nargs="*",
        help="Optional explicit paths (skip git diff when given)",
    )
    args = parser.parse_args(argv)
    mapping = load_map(args.map)

    if args.check_complete:
        missing = check_complete(mapping)
        if missing:
            print("Unmapped in-scope paths (strict impact map):", file=sys.stderr)
            for path in missing:
                print(f"  {path}", file=sys.stderr)
            return 2
        print(f"impact map complete ({len(iter_production_gd())} paths)")
        return 0

    base = args.base.strip()
    if not base:
        env_base = os.environ.get("GITHUB_BASE_REF", "").strip()
        base = f"origin/{env_base}" if env_base else "origin/main"

    paths = list(args.paths) if args.paths else _git_diff_names(base)
    full, suites, unmapped = select(paths, mapping)
    if unmapped:
        print("Strict impact map: unmapped changed paths:", file=sys.stderr)
        for path in unmapped:
            print(f"  {path}", file=sys.stderr)
        print(
            "Add a rule in tests/impact_map.toml (domain or full=true).",
            file=sys.stderr,
        )
        return 2

    if args.github_output:
        write_github_output(full, suites)
        out_dir = ROOT / ".gd-tools"
        out_dir.mkdir(parents=True, exist_ok=True)
        list_path = out_dir / "impact-suites.txt"
        if full:
            list_path.write_text("ALL\n", encoding="utf-8")
        else:
            list_path.write_text("".join(f"{s}\n" for s in suites), encoding="utf-8")

    if full:
        print("ALL")
        if args.print_command:
            print("gd-tools test --coverage --parallel 4 --timeout 240")
        return 0

    if not suites:
        print("NONE")
        return 0

    for suite in suites:
        print(suite)
    if args.print_command:
        joined = " ".join(suites)
        print(f"gd-tools test --coverage --parallel 4 --timeout 240 {joined}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
