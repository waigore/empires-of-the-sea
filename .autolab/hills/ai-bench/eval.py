"""Frozen evaluator for Empires of the Sea rival-court AI (ai-bench).

Runs a headless BENCH campaign: one subject crown (submission AI) vs two
baseline rivals (planners from origin/main) vs three random courts. Scores
only the subject's weighted progress. The climber may read this file.
"""

from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HILL = Path(__file__).resolve().parent
REPO_ROOT = HILL.parents[2]  # .autolab/hills/ai-bench → repo root
SYNC_SCRIPT = REPO_ROOT / "tools" / "sync_ai_mainline.py"

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

# Ignore generated mainline tree when hashing the submission surface.
AI_SURFACE_SKIP_PREFIXES = (
    "scripts/ai_mainline/",
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
    base = root.resolve()
    files: list[Path] = []
    for pattern in AI_SURFACE_GLOBS:
        files.extend(p for p in base.glob(pattern) if p.is_file())
    kept: list[Path] = []
    for path in files:
        rel = path.resolve().relative_to(base).as_posix()
        if any(rel.startswith(prefix) for prefix in AI_SURFACE_SKIP_PREFIXES):
            continue
        kept.append(path.resolve())
    return sorted({p for p in kept}, key=lambda p: str(p))


def ai_surface_hash(root: Path) -> str:
    base = root.resolve()
    h = hashlib.sha256()
    for path in ai_surface_files(base):
        rel = path.relative_to(base).as_posix()
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
        if str(row.get("court_kind", "")) == "subject":
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


def _funded_share(turns_path: Path, faction: int) -> float:
    """Mean share of top-ranked objectives the ledger funded, per resolved turn.

    The turn trace carries the court's objective ledger (`last.objectives`):
    `ranked` counts the aims that competed and `funded` the ones the allocator
    paid for. A rank-then-allocate change that ranks priorities but never funds
    them shows up here as a collapse — the #476 failure mode, made measurable
    (issue #491 T6).
    """
    if not turns_path.is_file():
        return 0.0
    shares: list[float] = []
    for line in turns_path.read_text().splitlines():
        if not line.strip():
            continue
        record = json.loads(line)
        for candidate in record.get("rows") or []:
            if int(candidate.get("faction", -2)) != faction:
                continue
            ledger = (candidate.get("last") or {}).get("objectives") or {}
            ranked = int(ledger.get("ranked", 0))
            if ranked <= 0:
                continue
            funded = int(ledger.get("funded", 0))
            shares.append(100.0 * float(funded) / float(ranked))
    if not shares:
        return 0.0
    return sum(shares) / len(shares)


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
    funded_pct = 0.0
    if turns_path is not None:
        income_pt, extraction_pt = _rates_from_turns(turns_path, faction)
        funded_pct = _funded_share(turns_path, faction)

    parts = {
        "provinces_old": provinces_old,
        "provinces_new": provinces_new,
        "regiments": regiments,
        "ships": ships,
        "workers": workers,
        "extraction_per_turn": extraction_pt,
        "income_per_turn": income_pt,
        "funded_pct": funded_pct,
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
        "funded_pct": float(funded_pct),
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


def _origin_main_sha(project: Path) -> str:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "origin/main^{commit}"],
            cwd=project,
            text=True,
        ).strip()
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(
            "origin/main is required for ai-bench baselines "
            f"(git rev-parse failed: {exc})"
        ) from exc


def _copy_frozen_mainline(dest: Path) -> str:
    frozen = HILL / "baseline_planners"
    if not frozen.is_dir() or not any(frozen.glob("*.gd")):
        raise RuntimeError(
            "hill baseline_planners/ missing; run "
            "python3 tools/sync_ai_mainline.py --dest "
            ".autolab/hills/ai-bench/baseline_planners"
        )
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(frozen, dest)
    sha_path = dest / ".mainline_sha"
    if sha_path.is_file():
        return sha_path.read_text().strip()
    return "frozen"


def _sync_mainline(dest_project: Path, git_repo: Path) -> str:
    dest = dest_project / "scripts" / "ai_mainline"
    script = dest_project / "tools" / "sync_ai_mainline.py"
    if not script.is_file():
        script = SYNC_SCRIPT
    # Prefer origin/main when the submission tree has git (local climbs).
    # Hills sandboxes often omit .git — fall back to the hill's frozen copy.
    git_dir = git_repo / ".git"
    if script.is_file() and (git_dir.is_dir() or git_dir.is_file()):
        proc = subprocess.run(
            [
                sys.executable,
                str(script),
                "--ref",
                "origin/main",
                "--repo",
                str(git_repo.resolve()),
                "--dest",
                str(dest),
            ],
            cwd=git_repo,
            capture_output=True,
            text=True,
        )
        if proc.returncode == 0:
            sha_path = dest / ".mainline_sha"
            if sha_path.is_file():
                return sha_path.read_text().strip()
            return _origin_main_sha(git_repo)
        # Fall through to frozen planners when origin/main is unavailable.
    return _copy_frozen_mainline(dest)


def _stage_project(submission: Path, stage: Path) -> str:
    """Copy submission into stage and materialize origin/main planners."""
    ignore = shutil.ignore_patterns(
        ".godot",
        ".git",
        "reports",
        "__pycache__",
        "*.pyc",
        ".venv",
        "venv",
        "build",
        "dist",
        "ai_mainline",
    )
    shutil.copytree(submission, stage, symlinks=True, ignore=ignore, dirs_exist_ok=True)
    sync_src = submission / "tools" / "sync_ai_mainline.py"
    if sync_src.is_file():
        (stage / "tools").mkdir(parents=True, exist_ok=True)
        shutil.copy2(sync_src, stage / "tools" / "sync_ai_mainline.py")
    # Git metadata stays on the submission tree; planners land in the stage.
    return _sync_mainline(stage, submission)


def _expected_roles(summary: dict) -> str | None:
    """Return an error string if BENCH role split is wrong; else None."""
    live = int(summary.get("ai_live", -1))
    rows = summary.get("rows") or []
    kinds: dict[int, str] = {}
    for row in rows:
        kinds[int(row.get("faction", -1))] = str(row.get("court_kind", ""))
    if live < 0:
        return "summary missing ai_live"
    if kinds.get(live) != "subject":
        return f"live faction {live} court_kind={kinds.get(live)!r}, expected subject"
    baselines = sorted(fid for fid, kind in kinds.items() if kind == "baseline")
    randoms = sorted(fid for fid, kind in kinds.items() if kind == "random")
    if len(baselines) != 2:
        return f"expected 2 baseline crowns, got {baselines}"
    if len(randoms) != 3:
        return f"expected 3 random crowns, got {randoms}"
    return None


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
                {"name": "funded_pct", "value": scored["funded_pct"], "direction": "max"},
            ],
            "config": config,
            "details": {
                "fixture": True,
                "ai_surface_hash": "fixture",
                **{
                    k: scored[k]
                    for k in (
                        "parts",
                        "early_win",
                        "live_faction",
                        "live_name",
                        "turn",
                        "resolved_turns",
                        "funded_pct",
                    )
                },
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
        stage = Path(tmp) / "project"
        out_dir = Path(tmp) / "out"
        out_dir.mkdir()
        try:
            mainline_sha = _stage_project(project, stage)
            _run_bench(stage, out_dir, turns, seed, size)
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
        role_err = _expected_roles(summary)
        if role_err:
            return _fail(role_err, config)
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
            {"name": "funded_pct", "value": scored["funded_pct"], "direction": "max"},
        ],
        "config": config,
        "details": {
            "fixture": False,
            "ai_surface_hash": surface,
            "mainline_git_sha": mainline_sha,
            **{
                k: scored[k]
                for k in (
                    "parts",
                    "early_win",
                    "live_faction",
                    "live_name",
                    "turn",
                    "resolved_turns",
                    "funded_pct",
                )
            },
        },
    }
