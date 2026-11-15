# The crown's walls

Every province the crown holds that can carry a fort, in one ledger — the wall
that meets an attack, the step the Engineer would take next, and the press that
files it.

**Pillars:** P1 (the level reads as a numeral), P2 (the price, the wait and the
gate are the fort table's own), P3 (pure projection), P5 (one press instead of
thirty dossiers).

**Wiki:** [siege-mechanics](https://github.com/waigore/empires-of-the-sea/wiki/siege-mechanics)
§ Fort Levels, § Wall Protection, § Emplaced Artillery. Decision: DR-20261116-01.

## Opening it

The realm ledger carries **Walls ›** (`V`) beside **Towns ›**. The realm prints
each province's fort level; this sheet prints the step that raises it, so the
door sits on the reading that raises the question
([`provinces.md`](provinces.md), [`towns.md`](towns.md)).

## What a row reads

| Line | Reads |
|------|-------|
| Medallion | the level as a numeral — `—` (open shore), `I`, `II`, `III` |
| Chip | `READY`, `AT WORK`, `NO ENGINEER`, `LOCKED`, `WALLED` |
| Note | `Next: stone fort · 4 lumber + 4 bronze · 2 turns`, the crew's own record, the study the order waits on, or the finished wall |

The chip names what the step waits on; the note is the step. The sheet states
the rule a crown pays by: 10 / 20 / 30 wall hp by level and 1–3 emplaced guns,
and the last gun falls even when an assault is repelled.

## Filters

Two chip rows — **chart** (both / Old World / New World) and **reading** (all /
ready / at work / walled) — each with its own tally; the count line names the
bare shores. The reading leads with what can be raised now, then what is in
hand, then what waits on a study, a crew or the stores, and the finished walls
last; the weakest wall leads.

## Raise

**Raise** sends the nearest idle Engineer through the same `build_fort` order
the civilian panel files (`ImprovementOrders.build_fort` → `CivilianWork`),
swapping the chart first when the province lies on the other one. The order's
message reaches the court as the toast, and the row repaints as `AT WORK`. A row
that cannot be raised carries no press: the note names the wait — the study, the
crew, or the stores a `LOCKED` shore is short of.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/wall_ledger.gd` | projection, states, filters, summary, row copy |
| `scripts/map/map_play_walls.gd` | both charts' assembly, `Raise` |
| `scripts/ui/wall_ledger_panel.gd` | the sheet |
| `scripts/ui/wall_ledger_row.gd` | one wall |
| `scripts/ui/province_ledger_panel.gd` | the `Walls ›` door |

No figure is recomputed: the level and its guns are `FortRules`, the price is
`FortRules.cost`, the wait is `FortRules.turns`, and the gate is
`CivilianWorkPlan.fort_refusal` — the wording the order itself refuses with
(`REQ-P2-03`).

## Tests

`tests/test_wall_ledger.gd` — the projection over both charts, every state, the
tallies and the reading order, the rule note, and the sheet: door, Raise, back
and key. `tests/test_ledgers.gd` reads its prose at desktop and phone widths.
