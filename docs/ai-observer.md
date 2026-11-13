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
`--ai=full|noop|bench` (planner gate), `--live=ID` (BENCH live crown;
default setup faction), `--out=DIR` (default `user://ai_vs_ai`).

## Planner modes (`AiControl`)

| Mode | Behaviour |
|------|-----------|
| `full` | Every Great Power runs the shared planners (default) |
| `noop` | Every Great Power issues no planner orders (inert control) |
| `bench` | Only the live crown plans; other GPs are no-op controls |

Use `bench` for quantitative win-seeking checks (live AI vs idle rivals).
Official scored climbs use hills **`ai-bench`** (`.autolab/hills/ai-bench/`).

## Metrics

Every crown — the former human slot included — is driven by the shared
planners when `ai_plans` allows (`AiTurn`, `AiMilitaryPlanner`,
`AiNavalPlanner`, `AiEconomyPlanner`, `AiCivilianPlanner`).
`MapPlayObserver.snapshot` reports per crown: leader, agenda, profile, whether
it plans, war footing, provinces / victory progress, power, forces, ledger,
wars, last-turn order mix. Dashboard: recent-orders feed, pause / step /
speed, campaign result. `play.ai_turns` keeps one merged record per turn
(wiki: turn-trace-interpretation).

Each row also carries `objectives`: the court's last ledger in one compact
row — `ranked` / `funded` over the whole tree and `top_ranked` / `top_funded`
over its top-level aims. The ai-bench evaluator reads the live crown's
`top_funded / top_ranked` per resolved turn and reports the mean as
`funded_pct` (issue #501): the share of the objectives the ledger ranked first
that it actually funded. Turns where the court ranked no top-level aim are
skipped, not counted as 1.0. `tools/check_ai_bench_report.py` fails the
`ai-bench-report` gate when `funded_pct` drops below the committed baseline,
so a rank-then-allocate change cannot silently re-starve the top aims (#476).

## Export

`tools/ai_vs_ai.gd` writes `run_NN_turns.jsonl` and `run_NN_summary.json`
(includes `ai_mode` / `ai_live`) and prints a win-rate / average-provinces
table across runs.

## Scope

Rival fog and colonisation planners are live under `full`/`bench` live crowns
(`CourtCharts`, `AiColonisationPlanner`). Ranked gaps: [`deferred.md`](deferred.md).
