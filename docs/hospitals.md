# The crown's hospitals

Every province the crown holds that can carry a ward, in one ledger — the level,
whether its staff ate, the next step, and the press that files it.

**Pillars:** P1 (the level reads as a numeral), P2 (the price, the wait and the
gate are the ward table's own), P3 (pure projection), P5 (one press instead of
thirty dossiers).

**Wiki:** [combat](https://github.com/waigore/empires-of-the-sea/wiki/combat)
§ Regiment condition. Decision: DR-20261116-02.

## Opening it

The realm ledger carries **Hospitals ›** beside **Towns ›** and **Walls ›**. The
realm prints each province's ward; this sheet prints the step that raises it, so
the door sits on the reading that raises the question
([`provinces.md`](provinces.md), [`towns.md`](towns.md), [`walls.md`](walls.md)).

## What a row reads

| Line | Reads |
|------|-------|
| Medallion | the level as a numeral — `—` (no ward), `I`, `II` |
| Chip | `READY`, `AT WORK`, `NO ENGINEER`, `LOCKED`, `WARDED` |
| Place | `Field hospital · rest 40% · wear 80% · staff 2 food`, or `unstaffed` |
| Note | `Next: field hospital · 3 lumber + 2 fabric · 1 turn`, the crew's own record, the study or the stores the order waits on, or the finished ward |

The sheet states the rule a crown pays by: rest 40% / 55% and the wear a defeat
leaves cut to 80% / 65%, and a staff that eats 2 food a turn per level — a ward
the larder cannot cover goes unfed and heals nothing that turn.

## Filters

Two chip rows — **chart** (both / Old World / New World) and **reading** (all /
ready / at work / warded) — each carrying its own tally. The count line names
how many shores keep **no ward**, what the whole staff eats a turn, and how many
wards went **unfed**. The reading leads with what can be raised now, then what
is in hand, then what waits, the finished wards last; the weakest ward leads.

## Raise

**Raise** sends the nearest idle Engineer through the same `build_hospital`
order the civilian panel files (`ImprovementOrders.build_hospital` →
`CivilianWork`), swapping the chart first when the province lies on the other
one. The order's message reaches the court as the toast, and the row repaints as
`AT WORK`. A row that cannot be raised carries no press: the note names the wait.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/hospital_ledger.gd` | projection, states, filters, summary, row copy |
| `scripts/map/map_play_hospitals.gd` | both charts' assembly, `Raise` |
| `scripts/ui/hospital_ledger_panel.gd` | the sheet |
| `scripts/ui/hospital_ledger_row.gd` | one ward |
| `scripts/ui/province_ledger_panel.gd` | the `Hospitals ›` door |

No figure is recomputed: the level, the rest share, the triage and the ration
are `HospitalRules`, the price is `HospitalRules.cost`, the wait is
`HospitalRules.turns`, and the gate is `CivilianWorkPlan.hospital_refusal` — the
wording the order itself refuses with (`REQ-P2-03`).

## Tests

`tests/test_hospital_ledger.gd` — the projection, every state, the stores gate,
the tallies, the rule note, and the sheet.
