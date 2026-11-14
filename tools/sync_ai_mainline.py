#!/usr/bin/env python3
"""Materialize scripts/ai_mainline/ from origin/main (or a ref) for ai-bench.

Copies scripts/ai/**/*.gd, renames every class_name Ai* → MainlineAi*, and
rewrites Ai* identifiers inside those files so the tree coexists with the
submission AI surface. Used by the ai-bench evaluator and local bench runs.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "scripts" / "ai_mainline"
DEFAULT_REF = "origin/main"
_REPO: Path = ROOT

CLASS_NAME_RE = re.compile(r"^class_name\s+(Ai\w+)\s*$", re.MULTILINE)
# Session-owned / harness types that must stay the submission class_name.
SKIP_CLASS_RENAMES = frozenset({"AiState"})
SKIP_FILES = frozenset({
    "ai_state.gd",  # shared session ledger
    "ai_control.gd",  # gate lives only on the submission surface
    "ai_bind.gd",
    "ai_random_court.gd",
})
# Longest Ai* class names first so AiParameterRegistry beats AiParameter.
AI_CLASS_NAMES: tuple[str, ...] = tuple(
    sorted(
        (
            "AiParameterRegistry",
            "AiColonisationPlanner",
            "AiHospitalTrainWork",
            "AiCivilianCandidate",
            "AiDiplomacyPlanner",
            "AiDiplomacyOffers",
            "AiMilitaryPlanner",
            "AiResearchPlanner",
            "AiInvasionPlanner",
            "AiCivilianPlanner",
            "AiEconomyPlanner",
            "AiDefensePlanner",
            "AiParameterPhase",
            "AiParameterArmy",
            "AiParameterCargo",
            "AiParameterMarket",
            "AiMarketPlanner",
            "AiPhasePlanner",
            "AiNavalPlanner",
            "AiCargoPlanner",
            "AiPeaceStance",
            "AiArmyReinforce",
            "AiExplorerWork",
            "AiEngineerWork",
            "AiHospitalWork",
            "AiMerchantWork",
            "AiBuilderWork",
            "AiTownRoads",
            "AiTurnLog",
            "AiSeaRoute",
            "AiSpyPlanner",
            "AiPersonality",
            "AiProfile",
            "AiControl",
            "AiAgenda",
            "AiIncome",
            "AiPower",
            # AiState stays unrenamed: the session owns one shared ledger object
            # that mainline planners must accept from map_play callv.
            "AiTurn",
            "AiConfig",
        ),
        key=len,
        reverse=True,
    )
)


def _git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=_REPO, text=True).strip()


def resolve_sha(ref: str) -> str:
    try:
        return _git("rev-parse", f"{ref}^{{commit}}")
    except subprocess.CalledProcessError as exc:
        raise SystemExit(f"sync_ai_mainline: cannot resolve {ref!r}: {exc}") from exc


def list_ai_gd(ref: str) -> list[str]:
    try:
        out = _git("ls-tree", "-r", "--name-only", ref, "scripts/ai")
    except subprocess.CalledProcessError as exc:
        raise SystemExit(f"sync_ai_mainline: cannot list {ref}:scripts/ai: {exc}") from exc
    return [line for line in out.splitlines() if line.endswith(".gd")]


def show_file(ref: str, path: str) -> str:
    return _git("show", f"{ref}:{path}")


def rewrite(source: str) -> str:
    def _class_name(match: re.Match[str]) -> str:
        name = match.group(1)
        if name in SKIP_CLASS_RENAMES:
            return match.group(0)
        return f"class_name Mainline{name}"

    text = CLASS_NAME_RE.sub(_class_name, source)
    for name in AI_CLASS_NAMES:
        text = re.sub(rf"\b{name}\b", f"Mainline{name}", text)
    # Avoid double-prefix if a file was already rewritten.
    text = text.replace("MainlineMainline", "Mainline")
    # Sibling preloads must load the mainline copy, not the submission surface.
    text = text.replace("res://scripts/ai/", "res://scripts/ai_mainline/")
    return text


def sync(dest: Path, ref: str, repo: Path | None = None) -> str:
    global _REPO
    _REPO = (repo or ROOT).resolve()
    sha = resolve_sha(ref)
    paths = list_ai_gd(ref)
    if not paths:
        raise SystemExit(f"sync_ai_mainline: no scripts/ai/*.gd under {ref}")
    if dest.exists():
        for stale in dest.rglob("*"):
            if stale.is_file():
                stale.unlink()
    dest.mkdir(parents=True, exist_ok=True)
    for rel in paths:
        name = Path(rel).name
        if name in SKIP_FILES:
            continue
        body = rewrite(show_file(ref, rel))
        out = dest / name
        out.write_text(body)
    (dest / ".mainline_sha").write_text(sha + "\n")
    return sha


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ref", default=DEFAULT_REF, help="git ref (default: origin/main)")
    parser.add_argument(
        "--dest",
        type=Path,
        default=DEST,
        help=f"output directory (default: {DEST})",
    )
    parser.add_argument(
        "--repo",
        type=Path,
        default=ROOT,
        help="git working tree used to read --ref (default: repo root)",
    )
    args = parser.parse_args()
    sha = sync(args.dest.resolve(), args.ref, repo=args.repo.resolve())
    print(f"sync_ai_mainline: {args.ref} @ {sha[:12]} → {args.dest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
