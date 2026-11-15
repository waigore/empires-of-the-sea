# Full-AI observer (debug)

Pits every Great Power against the others with no human court: an empty human
slot set makes the whole session AI (wiki: game-setup § Human/AI slot
assignment). New-game defaults otherwise — seed 1500, Standard map, six crowns.

Not a player mode: saving is disabled, consent decisions never queue, battles
auto-resolve, and the campaign may run past the 1800 cap (DR-20261108-05).

## Entry points

| Path | Use |
|------|-----|
| Title screen → `AI OBSERVER (DEBUG)` | Live dashboard over the real map |
| `tools/ai_vs_ai.gd` | Headless batch runs + JSON export |

```bash
godot --headless --path . --script res://tools/ai_vs_ai.gd -- \
  --turns=60 --seed=1500 --size=1 --runs=1 --ai=full
```

Options: `--turns`, `--seed`, `--size` (0 Small / 1 Standard / 2 Large),
`--runs` (seeds `seed+i`), `--historical` (stop at the calendar cap),
`--ai=full|noop|bench` (planner gate), `--live=ID` (BENCH subject;
default setup faction), `--out=DIR` (default `user://ai_vs_ai`),
`--budget=S` (per-run wall-clock budget, default 420).

## Performance budget

**One 200-turn run must finish in ≤ 7 minutes** wall clock (bench: seed 1500,
Standard, `--ai=bench`). Every AI change is validated on it, so a run that
outgrows the budget is a defect, not a slow machine.

The harness reports what it spent, line by line:

```text
Elapsed: 104.3s for 1 run(s) · 104.3s per run · budget 420s per run
```

An over-budget run still scores normally and is named `OVER BUDGET` on stderr.

What keeps a headless run inside it (keep these when editing):

| Lever | Why |
|-------|-----|
| `MapPlayTurn.view_live = false` | No chart on screen: the turn skips the lens/dossier/panel follow-up and the civilian marker sync. Rules outcome is unchanged. |
| Grouped estate ledger | `EstateRows.project` reads the network walk the ledger already made instead of re-seeding a BFS per disconnected tile. |

A new per-turn full-map scan (a fresh `LandConnectivity.resolve`, an
`ImprovementLedger.snapshot` per unit) is what pushes a run over budget.

Local bench needs mainline planners once:

`python tools/sync_ai_mainline.py`

## Planner modes (`AiControl`)

| Mode | Behaviour |
|------|-----------|
| `full` | Every Great Power runs the shared planners (default) |
| `noop` | Every Great Power issues no planner orders (inert control) |
| `bench` | Subject (live) = submission AI; two baselines = `origin/main` planners in `scripts/ai_mainline/`; three fillers = random legal economy/civilian actions |

Official scored climbs use hills **`ai-bench`** (`.autolab/hills/ai-bench/`).
The hill scores **only the subject**.

## Metrics

Every crown — the former human slot included — is driven when `AiControl.plans`
allows. `MapPlayObserver.snapshot` reports per crown: leader, agenda, profile,
`court_kind`, whether it plans, war footing, provinces / victory progress,
power, forces, ledger, wars, last-turn order mix. Dashboard: recent-orders
feed, pause / step / speed, campaign result. `play.ai_turns` keeps one merged
record per turn (wiki: turn-trace-interpretation).

## Export

`tools/ai_vs_ai.gd` writes `run_NN_turns.jsonl` and `run_NN_summary.json`
(includes `ai_mode` / `ai_live` / `ai_baselines`) and prints a win-rate /
average-provinces table across runs.

## Scope

Rival fog and colonisation planners are live under `full` and BENCH subject /
baseline crowns (`CourtCharts`, `AiColonisationPlanner`). Ranked gaps:
[`deferred.md`](deferred.md).
