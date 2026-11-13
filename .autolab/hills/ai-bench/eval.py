"""Frozen evaluator for Empires of the Sea rival-court AI (ai-bench).

Runs a headless bench campaign (one planning crown vs idle rivals) and scores
how far the live crown gets toward winning. The climber may read this file.
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

HILL = Path(__file__).resolve().parent

# Weights: provinces dominate, then forces, workforce, extraction, income.
W_PROVINCES_OLD = 100.0
W_PROVINCES_NEW = 50.0
W_REGIMENTS = 10.0
W_SHIPS = 10.0
W_WORKERS = 5.0
W_EXTRACTION = 2.0
W_INCOME = 1.0
W_EARLY_WIN = 500.0

AI_SURFACE_GLOBS = (
    "scripts/ai/**/*.gd",
    "scripts/map/map_play_*ai*.gd",
)


def _fail(error: str, config: list[dict]) -> dict:
    return {
        "passed": False,
        "metrics": [],
        "config": config,
        "details": {"error": error},
    }


def _config(turns: int, seed: int, size: int, mode: str) -> list[dict]:
    return [
        {"name": "mode", "value": mode, "primary": True},
        {"name": "turns", "value": turns, "primary": True},
        {"name": "seed", "value": seed, "primary": True},
        {"name": "size", "value": size, "primary": True},
        {"name": "ai", "value": "bench", "primary": True},
    ]


def ai_surface_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for pattern in AI_SURFACE_GLOBS:
        files.extend(p for p in root.glob(pattern) if p.is_file())
    return sorted({p.resolve() for p in files}, key=lambda p: str(p))


def ai_surface_hash(root: Path) -> str:
    h = hashlib.sha256()
    for path in ai_surface_files(root):
        rel = path.relative_to(root).as_posix()
        h.update(rel.encode())
        h.update(b"\0")
        h.update(path.read_bytes())
        h.update(b"\0")
    return "sha256:" + h.hexdigest()


def _live_row(summary: dict) -> dict | None:
    rows = summary.get("rows") or []
    live = int(summary.get("ai_live", -1))
    if live >= 0:
        for row in rows:
            if int(row.get("faction", -2)) == live:
                return row
    for row in rows:
        if bool(row.get("plans")):
            return row
    return rows[0] if rows else None


def _rates_from_turns(turns_path: Path, faction: int) -> tuple[float, float]:
    """Mean positive treasury / stock deltas per turn for the live crown."""
    if not turns_path.is_file():
        return 0.0, 0.0
    prev_treasury: int | None = None
    prev_stock: int | None = None
    income_vals: list[float] = []
    extract_vals: list[float] = []
    for line in turns_path.read_text().splitlines():
        if not line.strip():
            continue
        record = json.loads(line)
        row = None
        for candidate in record.get("rows") or []:
            if int(candidate.get("faction", -2)) == faction:
                row = candidate
                break
        if row is None:
            continue
        treasury = int(row.get("treasury", 0))
        stock = int(row.get("stock", 0))
        if prev_treasury is not None:
            delta_t = treasury - prev_treasury
            if delta_t > 0:
                income_vals.append(float(delta_t))
        if prev_stock is not None:
            delta_s = stock - prev_stock
            if delta_s > 0:
                extract_vals.append(float(delta_s))
        prev_treasury = treasury
        prev_stock = stock
    income = sum(income_vals) / len(income_vals) if income_vals else 0.0
    extraction = sum(extract_vals) / len(extract_vals) if extract_vals else 0.0
    return income, extraction


def score_summary(summary: dict, turns_path: Path | None = None) -> dict:
    row = _live_row(summary)
    if row is None:
        raise ValueError("summary has no crown rows")
    faction = int(row["faction"])
    provinces_old = int(row.get("provinces_old", 0))
    provinces_new = int(row.get("provinces_new", 0))
    regiments = int(row.get("regiments", 0))
    ships = int(row.get("ships", 0))
    workers = int(row.get("workers", 0))
    income_pt, extraction_pt = (0.0, 0.0)
    if turns_path is not None:
        income_pt, extraction_pt = _rates_from_turns(turns_path, faction)

    parts = {
        "provinces_old": provinces_old,
        "provinces_new": provinces_new,
        "regiments": regiments,
        "ships": ships,
        "workers": workers,
        "extraction_per_turn": extraction_pt,
        "income_per_turn": income_pt,
    }
    score = (
        W_PROVINCES_OLD * provinces_old
        + W_PROVINCES_NEW * provinces_new
        + W_REGIMENTS * regiments
        + W_SHIPS * ships
        + W_WORKERS * workers
        + W_EXTRACTION * extraction_pt
        + W_INCOME * income_pt
    )
    winner = int(summary.get("winner", -1))
    early_win = bool(summary.get("campaign_over")) and winner == faction
    if early_win:
        score += W_EARLY_WIN
    provinces = provinces_old + provinces_new
    forces = regiments + ships
    return {
        "score": float(score),
        "provinces": float(provinces),
        "forces": float(forces),
        "parts": parts,
        "early_win": early_win,
        "live_faction": faction,
        "live_name": str(row.get("name", "")),
        "turn": int(summary.get("turn", 0)),
        "resolved_turns": int(summary.get("resolved_turns", 0)),
    }


def _find_godot() -> str:
    env = os.environ.get("GODOT", "").strip()
    if env:
        return env
    which = shutil.which("godot")
    if which:
        return which
    raise FileNotFoundError("godot not found on PATH (set GODOT=...)")


def _run_bench(project: Path, out_dir: Path, turns: int, seed: int, size: int) -> None:
    godot = _find_godot()
    run_sh = project / "tools" / "run.sh"
    cmd: list[str]
    if run_sh.is_file():
        cmd = [
            str(run_sh),
            "--headless",
            "--script",
            "res://tools/ai_vs_ai.gd",
            "--",
            f"--turns={turns}",
            f"--seed={seed}",
            f"--size={size}",
            "--runs=1",
            "--ai=bench",
            "--quiet",
            f"--out={out_dir}",
        ]
    else:
        cmd = [
            godot,
            "--headless",
            "--path",
            str(project),
            "--script",
            "res://tools/ai_vs_ai.gd",
            "--",
            f"--turns={turns}",
            f"--seed={seed}",
            f"--size={size}",
            "--runs=1",
            "--ai=bench",
            "--quiet",
            f"--out={out_dir}",
        ]
    env = os.environ.copy()
    env.setdefault("GODOT", godot)
    proc = subprocess.run(
        cmd,
        cwd=project,
        env=env,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        tail = (proc.stdout or "")[-2000:] + "\n" + (proc.stderr or "")[-2000:]
        raise RuntimeError(f"ai_vs_ai failed (exit {proc.returncode}):\n{tail}")


def eval(
    submission: Path,
    *,
    final: bool = False,
    turns: int = 200,
    seed: int = 1500,
    size: int = 1,
) -> dict:
    mode = "test" if final else "validation"
    config = _config(turns, seed, size, mode)

    fixture = submission / "fixture_summary.json"
    if fixture.is_file():
        summary = json.loads(fixture.read_text())
        turns_path = submission / "fixture_turns.jsonl"
        scored = score_summary(summary, turns_path if turns_path.is_file() else None)
        return {
            "passed": True,
            "metrics": [
                {"name": "score", "value": scored["score"], "direction": "max"},
                {"name": "provinces", "value": scored["provinces"], "direction": "max"},
                {"name": "forces", "value": scored["forces"], "direction": "max"},
            ],
            "config": config,
            "details": {
                "fixture": True,
                "ai_surface_hash": "fixture",
                **{k: scored[k] for k in ("parts", "early_win", "live_faction", "live_name", "turn", "resolved_turns")},
            },
        }

    project = submission
    if not (project / "project.godot").is_file():
        return _fail(
            "submission must be a Godot project root (project.godot) "
            "or a fixture directory with fixture_summary.json",
            config,
        )
    if not (project / "tools" / "ai_vs_ai.gd").is_file():
        return _fail("submission missing tools/ai_vs_ai.gd", config)

    surface = ai_surface_hash(project)
    with tempfile.TemporaryDirectory(prefix="ai-bench-") as tmp:
        out_dir = Path(tmp) / "out"
        out_dir.mkdir()
        try:
            _run_bench(project, out_dir, turns, seed, size)
        except FileNotFoundError as exc:
            return _fail(str(exc), config)
        except RuntimeError as exc:
            return _fail(str(exc), config)

        summary_path = out_dir / "run_00_summary.json"
        turns_path = out_dir / "run_00_turns.jsonl"
        if not summary_path.is_file():
            return _fail("ai_vs_ai produced no run_00_summary.json", config)
        summary = json.loads(summary_path.read_text())
        if str(summary.get("ai_mode", "")) != "bench":
            return _fail(f"expected ai_mode=bench, got {summary.get('ai_mode')!r}", config)
        try:
            scored = score_summary(summary, turns_path)
        except ValueError as exc:
            return _fail(str(exc), config)

    return {
        "passed": True,
        "metrics": [
            {"name": "score", "value": scored["score"], "direction": "max"},
            {"name": "provinces", "value": scored["provinces"], "direction": "max"},
            {"name": "forces", "value": scored["forces"], "direction": "max"},
        ],
        "config": config,
        "details": {
            "fixture": False,
            "ai_surface_hash": surface,
            **{k: scored[k] for k in ("parts", "early_win", "live_faction", "live_name", "turn", "resolved_turns")},
        },
    }
