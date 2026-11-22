# The crown's towns

Every town the crown holds, in both charts: its level in the realm's **Defence**
view, and the step the Builder would take next in the province dossier.

**Pillars:** P1 (numerals), P2 (the work plan's own price, wait and gate),
P3 (pure projection), P5 (one press, not thirty).

**Wiki:** [extraction-and-improvements](https://github.com/waigore/empires-of-the-sea/wiki/extraction-and-improvements)
§ Town manufacturing bonus, § Improvement build costs;
[civilian-units](https://github.com/waigore/empires-of-the-sea/wiki/civilian-units)
§ Builder `upgrade_town`. Decision: DR-20261115-12.

## Where it reads

The realm sheet ([`provinces.md`](provinces.md)) prints each province's town
level in its **Defence** view. The town sheet is gone (issue #1164); the step
that raises one is the **Upgrade Town** order on the province dossier, filed
through the same `ImprovementOrders.upgrade_town` the sheet used to press.

## What a step reads

| Line | Reads |
|------|-------|
| Level | the numeral the realm prints — `I`–`IV` |
| Gate | `READY`, `AT WORK`, `NO BUILDER`, `LOCKED`, `DEVELOPED` |
| Note | `Next: II · 4 lumber + 4 cast iron · 2 turns`, the crew's own record, or the study the order waits on |
| Payoff | `L2 pays 1 manufacture per 4 raw its own estates deliver · the Garments works need a level-2 town` (`TownTerms`) |

A level that pays nothing says so: `L3 pays no manufacture — it is the road to
L4`.

## Raise

**Upgrade Town** on the province dossier sends the nearest idle Builder through
`ImprovementOrders.upgrade_town`. The order's message reaches the court as the
toast, and the dossier's gate repaints as `AT WORK`. An order that cannot run
carries no press: the note names the wait — stores short, or another crew on the
town tile — in the order's own words.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/town_ledger.gd` | projection, states, row copy |
| `scripts/rules/town_terms.gd` | what a level pays |
| `scripts/ui/province_raise_presses.gd` | the dossier's `Upgrade Town` order |

No figure is recomputed: price is `CivilianWork.cost_for`, wait
`CivilianWorkPlan.duration_for`, gate `town_upgrade_refusal`, crew the work
record (`REQ-P2-03`).

## Tests

`tests/test_ledgers.gd` — the towns cases read the projection over both charts,
every state, the tallies and the reading order.
