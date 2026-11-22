# The world's colonies

Every Tribe a Great Power has bought — who holds it, where it stands, what its
boycott shuts.

**Pillars:** P1, P2, P3, P5.

**Wiki:** [diplomacy](https://github.com/waigore/empires-of-the-sea/wiki/diplomacy)
§ GP–Tribe Rules — Join Empire, § Boycott. Decisions: DR-20261117-02,
DR-20261121-16, DR-20261121-18, DR-20261123-02.

## Opening it

**COLONIES ›** sits beside **EYES ›** on the court ledger; the letters are spent.

## What a row reads

| Line | Reads |
|------|-------|
| Chip | `OURS`, `SEALED`, `PAYS`, `COLONY` |
| Name | the people's own name (`The Inca`) |
| Detail | `<capital> — colony of <court>`, then the chart |
| Standing | the herald's word with the people, and their subsidy |
| Reading | their provinces, and `Open to every court` or `Sealed to …` |

**Visit** frames a colony's capital — a colony keeps its land.

## The court's own chain

One gold line under the chips: the Tribe the crown's own envoy is drawing in —
`The court would offer the Guaraní a Trade Consulate this turn, one link toward
a colony.` At war it names the gate, a missing study the door, a refused link
the rule's reason. The reading is `AiTribeColony.best`, held to `DiplomacyRules.can_establish_overture`
— the gate every envoy row answers.

It answers to the envoy's one order too: a chain that order did not take reads
`The court's chain with the Aztec waits this turn — its one order goes to
England.` The wait is the staff's, not a rule.

**The door:** a Tribe the crown has not bought has no row here, so the line
carries **Open the court**, which opens THE COURT on the court it names and sets
this sheet aside; no press when the line names none (a footing at war). It
orders nothing.

## Filters

Two chip rows — **chart** and **reading** (all / ours / sealed / subsidised) —
each with a tally; the crown's colonies lead, then sealed, then by court, one
heading per chart.

**The rule on the sheet:** a boycott shuts every colony of the issuer to the
boycotted court — no deal clears, aid and deeds refused, terms worsen 10%. A
people the crown has not met prints no row (`Unknown faction`); a colony prints
once the crown knows its people or court.

## What it never does

No deed, overture, boycott or lift is filed and no save key moves.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/colony_ledger.gd` | projection, filters, readings, rule |
| `scripts/map/map_play_colonies.gd` | both charts, the crown's record |
| `scripts/map/map_play_colony_pick.gd` | the chain, worded; its door |
| `scripts/map/map_play_diplomacy.gd` | the door: THE COURT on one court |
| `scripts/ui/colony_ledger_panel.gd` | the sheet |
| `scripts/ui/colony_ledger_row.gd` | one colony |

The suzerain is `DiplomacyState.colony_of`, the subsidy `DiplomacyState.subsidy`,
the step `DiplomacyCatalog.BOYCOTT_TERMS`, the bar the same boycott keys
(`REQ-P2-03`).

## Tests

`tests/test_ledgers.gd` — the projection, filters and tallies, both row shapes,
the chain and its gates, the envoy's one order, Visit, and the line's door.
