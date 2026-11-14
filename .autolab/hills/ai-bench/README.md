# ai-bench

Score Empires of the Sea’s rival-court AI on a fixed headless **bench**
campaign: one **subject** crown (submission planners) against two **baseline**
rivals (planners from `origin/main`) and three **random** courts. Higher scores
mean the subject got further toward winning within the turn cap — provinces
first, then forces, workforce, and economy rates.

This number stands in for a competitive, win-seeking AI under the same rules
the player uses. It is a proxy: a single seed can be overfit, and random fillers
are noisy opponents.

## What you may change

Edit only the **AI surface** inside a Godot project submission:

- `scripts/ai/**` (except generated `scripts/ai_mainline/`)
- `scripts/map/map_play_*ai*.gd`

You may retune registry knobs, rewrite planners, or change AI wiring. Do not
edit the hill, this evaluator, scoring weights, the CI report gate, or game
rules outside that surface.

## Submission format

A submission is a **directory** that is either:

```
project.godot          # full game checkout (normal climb)
scripts/ai/...
scripts/map/...
tools/ai_vs_ai.gd
…
```

or a fixture used only by hill tests:

```
fixture_summary.json   # MapPlayObserver final snapshot (+ run meta)
fixture_turns.jsonl    # optional per-turn snapshots
```

Official climbs score the repo root: `hills eval . -H ai-bench`.

## Metric

Evaluator stages a temp copy, materializes `scripts/ai_mainline/` from
`origin/main` when git is available (`tools/sync_ai_mainline.py`), else from
the hill’s frozen `baseline_planners/`, runs `tools/ai_vs_ai.gd` (`--ai=bench`),
and scores **only the subject** row (`ai_live` / `court_kind=subject`).

| metric      | direction | meaning                                      |
|-------------|-----------|----------------------------------------------|
| `score`     | max       | weighted progress (primary)                  |
| `provinces` | max       | subject province count (tie-break)           |
| `forces`    | max       | regiments + ships (tie-break)                |

Weights (frozen): Old World provinces ×100, New World ×50, regiments ×10,
ships ×10, workers ×5, mean positive stock Δ/turn ×2, mean positive treasury
Δ/turn ×1, plus +500 if the subject wins before the cap.

Roles (frozen): subject = live crown; baselines = two smallest other GP ids;
random = remaining three. Subject keeps its real score even if a random court
outranks it.

## Parameters

| param   | default | meaning                          |
|---------|---------|----------------------------------|
| `turns` | 200     | resolved-turn cap                |
| `seed`  | 1500    | map seed (only official seed)    |
| `size`  | 1       | Standard map                     |

Primary config: mode, turns, seed, size, ai=bench. Reports only compare when
those match. Hardware is local; scores from other machines do not mix.

## Test mode

`--final` sets mode=test (same seed today — no private holdout). Use once for
a claim, not for fishing.

## What the evaluator will not do

- Trust a score the submission printed
- Let you change weights, seed, or bench mode inside a comparable run
- Run network installs into the hill environment
- Soften a failed Godot run into a partial score
- Score without a readable `origin/main` for baseline planners

Known shortcuts: hardcoding seed 1500, buffing only the live faction id,
inflating workers without provinces. Prefer real win-seeking play.
