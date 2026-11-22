# The crown's hospitals

Every province that can carry a ward: the level and the rest it buys, read as
part of the realm's **Defence** view, and the next step on the province
dossier.

**Pillars:** P1 (numerals), P2 (the ward table's own price, wait and gate),
P3 (pure projection), P5 (one press, not thirty).

**Wiki:** [combat](https://github.com/waigore/empires-of-the-sea/wiki/combat)
§ Regiment condition. Decision: DR-20261116-02.

## Where it reads

The realm sheet ([`provinces.md`](provinces.md)) prints each province's ward in
its **Defence** line, beside the fort and the ground. The ward sheet is gone
(issue #1164); the step that raises one is the province dossier's own order.

## What a step reads

| Line | Reads |
|------|-------|
| Level | the numeral the realm prints — `—` (no ward), `I`, `II` |
| Gate | `READY`, `AT WORK`, `NO ENGINEER`, `LOCKED`, `WARDED` |
| Place | `Field hospital · rest 40% · wear 80% · staff 2 food`, or `unstaffed` |
| Press | `Raise Ward · 3 lumber + 2 fabric` — the next ward's price |
| Note | what the next ward buys — `L1 rests 40%, wear 80%, staff 2 food (+15% rest, -20% wear, +2 food)` — or the order's own refusal |

The rule a crown pays by: rest 40% / 55%, the wear a defeat
leaves cut to 80% / 65%, and a staff that eats 2 food a turn per level — an
unfed ward still shelters the wounded, but the province rests at the field's 25%.

## Raise

The province dossier's ward order files the same `build_hospital` work the
civilian panel files (`ImprovementOrders.build_hospital` → `CivilianWork`); the
order's message is the toast. An order that cannot run carries no press: the
note names the wait — the study, the stores, or another crew on the town tile —
in the order's own words.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/hospital_ledger.gd` | projection, states, summary, row copy |
| `scripts/rules/hospital_rules.gd` | rest, wear and the ration table |
| `scripts/ui/province_orders_section.gd` | the dossier's ward order |

No figure is recomputed: the level, rest share, triage and ration are
`HospitalRules`, the price `HospitalRules.cost`, the wait `HospitalRules.turns`,
and the gate `CivilianWorkRefusals.hospital` — the order's own wording
(`REQ-P2-03`).

## Tests

`tests/test_ledgers.gd` — the projection, every state, the stores gate, the
tallies and the rule note.
