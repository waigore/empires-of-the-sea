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

The observer boots both theatres but the AI issues no warp crossings or colonial
settlement, so runs play out in the Old World until rival fog exploration lands
(`REQ-P2-02`). Live campaigns are bounded by military victory; the observer's
endless mode is the allowed exception.
