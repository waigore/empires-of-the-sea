# Victory

Military victory, Great Power defeat and the calendar end (wiki:
[victory](https://github.com/waigore/empires-of-the-sea/wiki/victory)).

**Pillars:** P2, P5.

## Implemented

- **Military victory** (`VictoryRules`): a Great Power holding **31 Old World
  provinces** wins; the human crown's bar is the level's published percentage
  (26 / 31 / 36 / 40), every rival keeps 31. Ties go to the smallest player id.
- **Check:** once per turn, after every phase; an already-decided campaign is
  never re-checked. `VictoryState` holds winner, type and turn.
- **Calendar end:** a Historical campaign halts on the cap turn (201, 1800)
  without a military winner; Endless never halts. The declared winner is the
  strictly highest power score, or no-one on a tie.
- **Defeat:** terminal fall of the human crown mounts the defeat plate and
  seals turns; an AI crown's fall removes it and the campaign continues.
- **The age's race** (`VictoryStandings`, DR-20261112-05): the Gazette's sheet
  states at its foot the crown's Old World holdings against its own bar, the
  leader and the calendar; the close of a turn names a crown within **three
  provinces** of its bar in the despatches. The race is ranked by distance to
  each crown's **own** bar, so at a harder level a rival holding fewer
  provinces can lead. The threshold is a reading of the check — no winner,
  gate, AI decision or save field moves, and a crown already on its bar is
  never merely warned. The seal opens the history screen on that live sheet
  (standing included); a past sheet in the archive prints no standing. The
  full-AI observer prints neither line.
- **Plates** (`VictoryOverlay`): one family for military victory, defeat and
  campaign complete; "view final state" keeps the map pannable and the pause
  menu reachable.

## Deferred (REQ-P2-02)

Alternative victory types (economic, scientific, peaceful, score) — wiki
out of scope. Ranked gaps: [`deferred.md`](deferred.md).

## Architecture

Rules: `victory_rules`, `victory_state`, `victory_standings`, `campaign_defeat`,
`defeat_state`, `turn_time`. Map glue: `map/map_play_campaign`,
`map/map_play_turn` (the check and the warning), `map/map_play_gazette` (the
sheet's standing). UI: `victory_overlay`, `gazette_plate` (the standing column).
Rules need no nodes (`REQ-P3-03`).

## Tests

Suites: `test_victory_standings`, `test_gazette_plate`, `test_victory_screen`,
`test_campaign_end`, `test_campaign_intro`, `test_campaign_defeat`,
`test_capital_loss`.

```bash
gd-tools test --coverage --min 80
```
