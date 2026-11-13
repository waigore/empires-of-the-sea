# The sea's despatch

A resolved sea battle the crown fought opens a plate: painted water, both
colours' hulls standing on it as their own medallions, and the engagement in
four beats.

**Pillars:** P1, P2 (view only), P5. **Wiki:**
[ships-and-naval](https://github.com/waigore/empires-of-the-sea/wiki/ships-and-naval)
§ Naval Combat Resolution.

## What it shows

| Part | Reads |
|------|-------|
| Headline | attacker against defender, and the zone (region-prefixed across charts) |
| Hull lines | one medallion per type, with the number that flew (`ShipArt`) |
| Bars | the strength the resolver struck with, then the hulls each colour carried out |
| Beats | the meeting, the maths (`Strength 182 against 121 — share 60 of 100`), the dead by name, what the sea decided |

## Rules it keeps

- Every number and name comes from the resolver's record (`NavalDispatch`);
  the plate never recomputes a rule (`REQ-P2-03`).
- One tap (Skip) tells the whole despatch; Continue hands the court back
  (`REQ-P5-06`). Held news waits for the last plate of the turn.
- Land resolves before sea, so a turn that fought on both elements replays one
  plate at a time, land first.
- A rival's battle stays the court's despatch lane alone: the plate is for the
  crown's own engagements.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/naval_dispatch.gd` | pure copy: groups, shares, beats, verdict |
| `scripts/rules/naval_combat.gd` | the record carries each side's hull types |
| `scripts/ui/naval_plate.gd` | the plate (view only) |
| `scripts/ui/{game_hud,hud_chrome}.gd` | mount, queue and held-news release |
| `scripts/map/map_play_naval_turn.gd` | raises the plate for the crown's battles |

Art: `assets/art/battle/sea_open.jpg` (generated, see
[`tools/art/battle-plate.md`](../tools/art/battle-plate.md)).

## Tests

`tests/test_naval_rules.gd` (copy and record), `tests/test_quick_battle_overlay.gd`
(plate, medallions, queue). Screenshot:
`godot --path . -s tests/naval_plate_shot.gd -- out=/tmp/sea.png`.
