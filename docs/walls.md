# The crown's walls

Every province the crown holds that can carry a fort: the wall that meets an
attack, read as the realm's **Defence** figure, and the step the Engineer would
take next on the province dossier.

**Pillars:** P1 (numerals), P2 (the fort table's own price, wait and gate),
P3 (pure projection), P5 (one press, not thirty).

**Wiki:** [siege-mechanics](https://github.com/waigore/empires-of-the-sea/wiki/siege-mechanics)
§ Fort Levels, § Wall Protection, § Emplaced Artillery. Decision: DR-20261116-01.

## Where it reads

The realm sheet ([`provinces.md`](provinces.md)) prints each province's fort
level and the guns its wall emplaces in the **Defence** view and figure. The wall
sheet is gone (issue #1164); the step that raises one is the province dossier's
own fort order.

## What a step reads

| Line | Reads |
|------|-------|
| Level | the numeral the realm prints — `—` (open shore), `I`, `II`, `III` |
| Gate | `READY`, `AT WORK`, `NO ENGINEER`, `LOCKED`, `WALLED` |
| Press | `Raise Wall · 4 lumber + 4 bronze` — the next level's price, from the fort table |
| Note | what the next wall buys — `L2 soaks 80 wall hp with 2 guns (+40 hp, +1 gun)` — or the order's own refusal |

The press names the price and prints what the wall buys under it, in words a
phone reads without a hover. The sheet states the rule off the fort table:
40 / 80 / 120 wall hp by level and 1–5 emplaced guns.

## Raise

The province dossier's fort order files the same `build_fort` work the civilian
panel files (`ImprovementOrders.build_fort` → `CivilianWork`); its message is the
toast. An order that cannot run carries no press: the note names the wait — the
study, the crew, or the stores that shore lacks.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/wall_ledger.gd` | projection, states, summary, row copy |
| `scripts/rules/realm_readings.gd` | the realm's defence figure and ground |
| `scripts/ui/province_orders_section.gd` | the dossier's fort order |

No figure is recomputed: the level and its guns are `FortRules`, as are the
price and the wait; the gate is `CivilianWorkRefusals.fort`, the wording the
order itself refuses with (`REQ-P2-03`).

## Tests

`tests/test_ledgers.gd` — the walls cases read the projection over both charts,
every state, the tallies, the reading order and the rule note.
