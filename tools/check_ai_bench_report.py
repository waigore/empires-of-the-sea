#!/usr/bin/env python3
"""CI gate: AI-surface PRs must ship a signed ai-bench report ≥ baseline.

Does not re-run Godot. Validates report shape, hill tree hash, AI-surface
binding, primary config, score vs committed baseline, and — when the report
carries it — the ledger's funded share vs baseline (issue #501).

Usage:
  python tools/check_ai_bench_report.py
  python tools/check_ai_bench_report.py --base origin/main
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HILL = ROOT / ".autolab" / "hills" / "ai-bench"
REPORT = ROOT / "reports" / "ai-bench" / "latest.json"
BASELINE = ROOT / "reports" / "ai-bench" / "baseline.json"

AI_GLOBS = (
    "scripts/ai/**/*.gd",
    "scripts/map/map_play_*ai*.gd",
)

# A funded share may wobble by rounding; a collapse is what the gate hunts.
FUNDED_EPSILON = 1e-6

EXPECTED_PRIMARY = {
    "mode": "validation",
    "turns": 200,
    "seed": 1500,
    "size": 1,
    "ai": "bench",
}


def _die(msg: str, code: int = 1) -> None:
    print(f"ai-bench-gate: {msg}", file=sys.stderr)
    raise SystemExit(code)


def _git(*args: str) -> str:
    r = subprocess.run(
        ["git", *args], cwd=ROOT, capture_output=True, text=True, check=False
    )
    if r.returncode != 0:
        _die(f"git {' '.join(args)} failed: {r.stderr.strip()}")
    return r.stdout.strip()


def _changed_paths(base: str) -> list[str]:
    out = _git("diff", "--name-only", "--diff-filter=ACMR", f"{base}...HEAD")
    return [line for line in out.splitlines() if line]


def _is_ai_path(path: str) -> bool:
    if path.startswith("scripts/ai/") and path.endswith(".gd"):
        return True
    name = Path(path).name
    if path.startswith("scripts/map/") and path.endswith(".gd") and "ai" in name:
        return True
    return False


def _ai_surface_hash(root: Path) -> str:
    files: list[Path] = []
    for pattern in AI_GLOBS:
        files.extend(p for p in root.glob(pattern) if p.is_file())
    files = sorted({p.resolve() for p in files}, key=lambda p: str(p))
    h = hashlib.sha256()
    for path in files:
        rel = path.relative_to(root).as_posix()
        h.update(rel.encode())
        h.update(b"\0")
        h.update(path.read_bytes())
        h.update(b"\0")
    return "sha256:" + h.hexdigest()


def _hill_tree_hash() -> str:
    # hills stores commits in .vc; ask the CLI when available.
    try:
        r = subprocess.run(
            ["hills", "describe", "ai-bench", "--json"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
    except FileNotFoundError:
        return ""
    if r.returncode != 0:
        return ""
    data = json.loads(r.stdout)
    return str(data.get("tree_hash") or data.get("tree") or "")


def _load_report(path: Path) -> dict:
    if not path.is_file():
        _die(f"missing report {path.relative_to(ROOT)}")
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        _die(f"invalid JSON in {path}: {exc}")


def _metric(report: dict, name: str) -> float:
    for entry in report.get("metrics") or []:
        if entry.get("name") == name:
            return float(entry["value"])
    _die(f"report missing metric {name!r}")


def _optional_metric(report: dict, name: str) -> float | None:
    """A metric that older reports may predate; None when absent."""
    for entry in report.get("metrics") or []:
        if entry.get("name") == name:
            return float(entry["value"])
    return None


def _primary(report: dict) -> dict:
    return {
        c["name"]: c["value"]
        for c in report.get("config") or []
        if c.get("primary")
    }


def _maybe_verify(report_path: Path) -> None:
    """Run hills verify when the CLI + key are present (local / shared-key CI)."""
    try:
        r = subprocess.run(
            ["hills", "verify", str(report_path), "--json"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
    except FileNotFoundError:
        print("ai-bench-gate: hills not installed — skip signature verify")
        return
    if r.returncode != 0:
        # Per-machine HMAC: expected to fail across hosts without a shared key.
        print(
            "ai-bench-gate: hills verify failed (ok on foreign hosts without "
            f"shared key): {r.stderr.strip() or r.stdout.strip()}"
        )
        return
    print("ai-bench-gate: hills verify OK")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--base",
        default="",
        help="git base ref for change detection (default: origin/main if fetchable)",
    )
    parser.add_argument(
        "--always",
        action="store_true",
        help="require a valid report even when no AI-surface files changed",
    )
    args = parser.parse_args()

    base = args.base
    if not base:
        base = "origin/main"
        subprocess.run(
            ["git", "fetch", "--no-tags", "origin", "main"],
            cwd=ROOT,
            capture_output=True,
            check=False,
        )

    if not args.always:
        changed = _changed_paths(base)
        ai_changed = [p for p in changed if _is_ai_path(p)]
        if not ai_changed:
            print("ai-bench-gate: no AI-surface changes — skip")
            return
        print("ai-bench-gate: AI paths changed:")
        for path in ai_changed:
            print(f"  {path}")

    report = _load_report(REPORT)
    baseline = _load_report(BASELINE)

    if report.get("hill") != "ai-bench":
        _die(f"report hill is {report.get('hill')!r}, expected 'ai-bench'")
    if not report.get("passed"):
        _die("report.passed is false")
    if not str(report.get("signature", "")).startswith("hmac-sha256:"):
        _die("report missing hmac-sha256 signature field")

    primary = _primary(report)
    for key, expected in EXPECTED_PRIMARY.items():
        if primary.get(key) != expected:
            _die(f"primary config {key}={primary.get(key)!r}, expected {expected!r}")

    details = report.get("details") or {}
    expected_hash = _ai_surface_hash(ROOT)
    got_hash = details.get("ai_surface_hash")
    if got_hash != expected_hash:
        _die(
            "ai_surface_hash mismatch — report is not bound to this tree's AI "
            f"surface.\n  report: {got_hash}\n  tree:   {expected_hash}"
        )

    tree = _hill_tree_hash()
    if tree and report.get("tree_hash") and report["tree_hash"] != tree:
        _die(
            f"report tree_hash {report['tree_hash']} != hill {tree} "
            "(re-score against the committed hill)"
        )

    score = _metric(report, "score")
    base_score = _metric(baseline, "score")
    if score + 1e-9 < base_score:
        _die(f"score {score} < baseline {base_score}")

    # The ledger's honesty: a rank-then-allocate change that silently re-starves
    # the top objectives must fail here even when the score holds (#501, #476).
    funded = _optional_metric(report, "funded_pct")
    base_funded = _optional_metric(baseline, "funded_pct")
    if funded is not None and base_funded is not None:
        if funded + FUNDED_EPSILON < base_funded:
            _die(
                f"funded_pct {funded:.4f} < baseline {base_funded:.4f} — the "
                "ledger stopped funding the objectives it ranks first"
            )

    _maybe_verify(REPORT)
    print(
        f"ai-bench-gate: OK score={score} baseline={base_score} "
        f"funded_pct={funded if funded is not None else 'n/a'} "
        f"surface={expected_hash[:19]}…"
    )


if __name__ == "__main__":
    main()
