# ai-bench

Score Empires of the Sea’s rival-court AI on a fixed headless **bench**
campaign: one planning crown against idle rivals. Higher scores mean the live
AI got further toward winning within the turn cap — provinces first, then
forces, workforce, and economy rates.

This number stands in for a competitive, win-seeking AI under the same rules
the player uses. It is a proxy: a single seed can be overfit, and idle rivals
are weaker than a full free-for-all.

## What you may change

Edit only the **AI surface** inside a Godot project submission:

- `scripts/ai/**`
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

Evaluator owns the clock and reads `run_00_summary.json` / turns JSONL from
`tools/ai_vs_ai.gd` (`--ai=bench`). Live crown = `ai_live` when set, else the
row with `plans: true`.

| metric      | direction | meaning                                      |
|-------------|-----------|----------------------------------------------|
| `score`     | max       | weighted progress (primary)                  |
| `provinces` | max       | live crown province count (tie-break)        |
| `forces`    | max       | regiments + ships (tie-break)                |

Weights (frozen): Old World provinces ×100, New World ×50, regiments ×10,
ships ×10, workers ×5, mean positive stock Δ/turn ×2, mean positive treasury
Δ/turn ×1, plus +500 if the live crown wins before the cap.

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

Known shortcuts: hardcoding seed 1500, buffing only the live faction id,
inflating workers without provinces. Prefer real win-seeking play.
