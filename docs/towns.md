# The crown's towns

Every town the crown holds, in both charts, in one ledger — the level it stands
at, the step the Builder would take next, and the press that files it.

**Pillars:** P1 (numerals), P2 (the work plan's own price, wait and gate),
P3 (pure projection), P5 (one press, not thirty).

**Wiki:** [extraction-and-improvements](https://github.com/waigore/empires-of-the-sea/wiki/extraction-and-improvements)
§ Town manufacturing bonus, § Improvement build costs;
[civilian-units](https://github.com/waigore/empires-of-the-sea/wiki/civilian-units)
§ Builder `upgrade_town`. Decision: DR-20261115-12.

## Opening it

The realm ledger carries **Towns ›** (`B`). The sheet is the muster roll's
sibling: its own modal layer, the same chrome, the same pause-door park
([`provinces.md`](provinces.md)). The realm prints each province's town level;
this sheet prints the step that raises it, so the door sits on the reading that
raises the question.

## What a row reads

| Line | Reads |
|------|-------|
| Medallion | the level as a numeral — `I`–`IV` |
| Chip | `READY`, `AT WORK`, `NO BUILDER`, `LOCKED`, `DEVELOPED` |
| Note | `Next: II · 4 lumber + 4 cast iron · 2 turns`, the crew's own record, the study the order waits on, or the finished town |

The sheet states the rule a crown pays by: a town pays manufactures at levels
**2 and 4** only — level 3 buys the road to 4 — from the raw its own estates
deliver.

## Filters

Two chip rows — **chart** (both / Old World / New World) and **reading** (all /
ready / at work / developed) — each carrying its own tally. The reading leads
with what can be raised now, then what is in hand, then what waits, the finished towns last;
within a state the cheapest step leads.

## Raise

**Raise** sends the nearest idle Builder through the province dossier's own
order (`ImprovementOrders.upgrade_town`), swapping the chart first when the
province lies on the other one. The order's message reaches the court as the
toast, and the row repaints as `AT WORK`. A row that cannot be raised carries no
press: the note names the wait — the stores a town cannot pay for, or another
crew already working the town tile (a wall or a ward rising there), in the
order's own words.

**Raise all ready (n)** files every ready row the view prints — arm once,
confirm once — in the sheet's order, and stops at the first refusal. One
receipt names what it raised and what waits (DR-20261116-03).

## Architecture

| File | Role |
|------|------|
| `scripts/rules/town_ledger.gd` | projection, states, filters, row copy |
| `scripts/map/map_play_towns.gd` | both charts' assembly, `Raise` |
| `scripts/ui/town_ledger_panel.gd` | the sheet |
| `scripts/ui/town_ledger_row.gd` | one town |
| `scripts/ui/province_ledger_panel.gd` | the `Towns ›` door |

No figure is recomputed: price is `CivilianWork.cost_for`, wait
`CivilianWorkPlan.duration_for`, gate `town_upgrade_refusal`, crew the work
record (`REQ-P2-03`).

## Tests

`tests/test_ledgers.gd` — the towns cases read the projection over both charts,
every state, the tallies and the reading order, and the door, Raise, back and
key.
