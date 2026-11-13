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
  --turns=60 --seed=1500 --size=1 --runs=1
```

Options: `--turns`, `--seed`, `--size` (0 Small / 1 Standard / 2 Large),
`--runs` (seeds `seed+i`), `--historical` (stop at the calendar cap),
`--out=DIR` (default `user://ai_vs_ai`).

## Metrics

Every crown — the former human slot included — is driven by the shared
planners (`AiTurn`, `AiMilitaryPlanner`, `AiNavalPlanner`, `AiEconomyPlanner`,
`AiCivilianPlanner`). `MapPlayObserver.snapshot` reports per crown:

- leader, agenda and profile
- war footing: `at war` (a Great Power war), `overstretched` (two or more) or
  `at peace` (`AiPhasePlanner`, DR-20261113-15)
- Old/New World provinces and progress toward the 31-province victory, plus rank
- public power score, regiments, ships, civilians
- treasury, stockpile, workers, researched techs
- wars and alliances, alive/fallen
- last turn's order mix and events

The dashboard also shows a recent-orders feed, pause / step / speed controls and
the campaign result. `play.ai_turns` keeps one merged record per resolved turn
(wiki: turn-trace-interpretation).

## Export

`tools/ai_vs_ai.gd` writes `run_NN_turns.jsonl` (one snapshot per turn) and
`run_NN_summary.json` (final standing, resolved turns) and prints a win-rate /
average-provinces table across runs.

## Scope

Rival fog and colonisation planners are live (`CourtCharts`,
`AiColonisationPlanner`): each crown's Explorer crosses a Passage and charts the
New World. No court settles or conquers there — an overseas invasion wants a
border free of war — so no riches reach a treasury and the Old World stays a
subsistence economy. Live campaigns are bounded by military victory; the
observer's endless mode is the allowed exception.
Ranked gaps: [`deferred.md`](deferred.md).
