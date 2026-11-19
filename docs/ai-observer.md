# Full-AI observer (debug)

Every Great Power runs under AI: an empty human slot set makes the whole session
AI (wiki: game-setup § Human/AI slot assignment); otherwise new-game defaults —
seed 1500, Standard, six crowns.

Not a player mode: saving is off, consent never queues, battles auto-resolve,
and the campaign may run past the 1800 cap (DR-20261108-05).

## Entry points

| Path | Use |
|------|-----|
| `-- --ai-observer` (desktop) | Live dashboard over the real map |
| `tools/ai_vs_ai.gd` | Headless batch runs + JSON export |

Desktop only: a handset always opens the title screen, and no menu carries this
door.

```bash
godot --path . -- --ai-observer
```

```bash
# Headless batch run + JSON export
godot --headless --path . --script res://tools/ai_vs_ai.gd -- \
  --turns=60 --seed=1500 --size=1 --runs=1 --ai=full
```

Options: `--turns`, `--seed`, `--size` (0/1/2),
`--runs` (seeds `seed+i`), `--historical` (stop at the calendar cap),
`--ai=full|noop|bench` (planner gate), `--live=ID` (BENCH subject; default setup
faction), `--out=DIR` (default `user://ai_vs_ai`), `--budget=S` (default 420).

## Performance budget

**One 200-turn run must finish in ≤ 7 minutes** (seed 1500, Standard,
`--ai=bench`); the harness prints its spend and names `OVER BUDGET` on
stderr. `view_live = false` skips the chart, dossier and panel follow-up, and the grouped estate ledger walks the network once. Bench needs
mainline planners once: `python tools/sync_ai_mainline.py`.

## Planner modes (`AiControl`)

| Mode | Behaviour |
|------|-----------|
| `full` | Every Great Power runs the shared planners (default) |
| `noop` | Every Great Power issues no planner orders (inert control) |
| `bench` | Subject = submission AI; two baselines = `origin/main` in `scripts/ai_mainline/`; three fillers = random legal actions |

Official climbs use hills **`ai-bench`** (`.autolab/hills/ai-bench/`),
scoring **only the subject**.

## Metrics

`MapPlayObserver.snapshot` reports per crown: leader, agenda, profile,
`court_kind`, war footing, provinces / victory progress, power, forces (hulls,
warships, holds), ledger, wars, last-turn order mix and the market's prices
(`minor_food`, `ration_demand`, `food_gap` — #766). Dashboard: the feed, pause /
step / speed, the result. `play.ai_turns` keeps one merged record per turn,
Combat's battles included (`BattleTrace`), so a siege reads without a plate
(wiki: turn-trace-interpretation). The feed prints **every row of the newest
whole turns**, newest first, and scrolls — it never picks which orders a watcher
may read. Its window is a **row budget** (`ROW_BUDGET` 120) with a two-turn
floor; the caption names the span (`T12–T17`). The window grows with the screen
(`FEED_SHARE` 0.3, capped 320), 128 points on a handset.

## Province reading

A tap on a charted province opens **the observer's province sheet**
(`ObserverProvince` → `ObserverProvinceSheet`): the court that holds it, the
ground, the town, the estates, the wall, the ward and the host there.
It is read-only — the observatory has no seat — and re-reads the open province
each turn.

## Export and coverage

`tools/ai_vs_ai.gd` writes `run_NN_turns.jsonl` and `run_NN_summary.json`
(`ai_mode` / `ai_live` / `ai_baselines`). It prints the **coverage checklist**
(`AiCoverage`): every shipped rival rule with count, crowns and window, and
`never`/`gated` when none did. `army.muster` and `navy.launch` also report aim
ranked vs funded. A **major** rule never exercised fails a `--ai=full` run
that reached its cap (#605).

## Scope

Rival fog and colonisation planners are live under `full` and BENCH crowns (`CourtCharts`, `AiColonisationPlanner`). Gaps:
[`deferred.md`](deferred.md).
