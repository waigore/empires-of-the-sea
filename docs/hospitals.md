# The crown's hospitals

Every province that can carry a ward, in one ledger — the level, whether its
staff ate, the next step and the press.

**Pillars:** P1 (numerals), P2 (the ward table's own price, wait and gate),
P3 (pure projection), P5 (one press, not thirty).

**Wiki:** [combat](https://github.com/waigore/empires-of-the-sea/wiki/combat)
§ Regiment condition. Decision: DR-20261116-02.

## Opening it

The realm ledger carries **Hospitals ›** beside **Towns ›** and **Walls ›**, on
the reading that raises the question ([`provinces.md`](provinces.md)).

## What a row reads

| Line | Reads |
|------|-------|
| Medallion | the level as a numeral — `—` (no ward), `I`, `II` |
| Chip | `READY`, `AT WORK`, `NO ENGINEER`, `LOCKED`, `WARDED` |
| Place | `Field hospital · rest 40% · wear 80% · staff 2 food`, or `unstaffed` |
| Note | `Next: field hospital · 3 lumber + 2 fabric · 1 turn`, the crew's own record, the study or the stores the order waits on, or the finished ward |

The rule a crown pays by: rest 40% / 55%, the wear a defeat
leaves cut to 80% / 65%, and a staff that eats 2 food a turn per level — an
unfed ward still shelters the wounded, but the province rests at the field's 25%.

## Filters

Two chip rows — **chart** (both / Old World / New World) and **reading** (all /
ready / at work / warded) — each with its own tally. The count line names
the shores with **no ward**, what the staff eats a turn, and how many wards went
**unfed**. The reading leads with what can be raised now, then what
is in hand, then what waits, the finished wards last; the weakest ward leads.

## Raise

**Raise** sends the nearest idle Engineer through the same `build_hospital`
order the civilian panel files (`ImprovementOrders.build_hospital` →
`CivilianWork`), swapping the chart first when the province lies on the other
one. The order's message is the toast, and the row repaints as
`AT WORK`. A row that cannot be raised carries no press: the note names the wait
— the study, the stores, or another crew on the town tile — in the order's own
words.

**Raise all ready (n)** files every ready row the view prints, arm then
confirm, stopping at the first refusal; the line under it prices the walk in each
chart's own Engineers and names the rows that wait (DR-20261116-03,
DR-20261118-12, DR-20261118-13).

## Architecture

| File | Role |
|------|------|
| `scripts/rules/hospital_ledger.gd` | projection, states, filters, summary, row copy |
| `scripts/map/map_play_hospitals.gd` | both charts' assembly, `Raise` |
| `scripts/ui/hospital_ledger_panel.gd` | the sheet |
| `scripts/ui/hospital_ledger_row.gd` | one ward |
| `scripts/ui/province_ledger_panel.gd` | the `Hospitals ›` door |

No figure is recomputed: the level, rest share, triage and ration are
`HospitalRules`, the price `HospitalRules.cost`, the wait `HospitalRules.turns`,
and the gate `CivilianWorkRefusals.hospital` — the order's own wording
(`REQ-P2-03`).

## Tests

`tests/test_ledgers.gd` — the projection, every state, the stores gate,
the tallies, the rule note, and the sheet.
