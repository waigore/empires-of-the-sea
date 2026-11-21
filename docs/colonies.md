# The world's colonies

Every Tribe a Great Power has bought — who holds it, where it stands, what its
boycott shuts.

**Pillars:** P1 sheet, P2 readings, P3 projection, P5 boycott home.

**Wiki:** [diplomacy](https://github.com/waigore/empires-of-the-sea/wiki/diplomacy)
§ GP–Tribe Rules — Join Empire, § Boycott. Decisions: DR-20261117-02,
DR-20261121-16.

## Opening it

The court ledger carries **COLONIES ›** beside **EYES ›**. No key: the letters
are spent.

## What a row reads

| Line | Reads |
|------|-------|
| Medallion | the globe: a people, not a province |
| Chip | `OURS`, `SEALED`, `PAYS`, `COLONY` |
| Name | the people's own name (`The Inca`) |
| Detail | `<capital> — colony of <court>`, then the chart |
| Standing | the herald's word with the people, and their subsidy |
| Reading | their provinces, and `Open to every court` or `Sealed to …` |

**Visit** frames the colony's capital; a colony keeps its land, so its seat is
on the chart.

## The court's own chain

One gold line under the chips: the Tribe the crown's own envoy is drawing in —
`The court would offer the Guaraní a Trade Consulate this turn, one link toward
a colony.` At war it names the gate; a missing study names the door; a link the
press would refuse names the rule's reason (`The court's chain with the Aztec
waits this turn (Join Empire needs a warmer court than this one).`). The reading
is `AiTribeColony.best` — the pass's own call — held to
`DiplomacyRules.can_establish_overture`, the gate every envoy row answers.

## Filters

Two chip rows — **chart** and **reading** (all / ours / sealed / subsidised) —
each with its tally. The crown's colonies lead, then the sealed, then by court;
one heading per chart.

**The rule on the sheet:** a boycott shuts every colony of the issuer to the
boycotted court — no deal clears, aid and deeds are refused, terms worsen 10%.
A colony keeps its provinces, its court and its trade.

## What it never does

No deed, overture, boycott or lift is filed, and no save key moves. The press
stays on the court's own page.

## No row without an envoy

A people the crown has not met prints no row (`Unknown faction`); a colony
prints when the crown knows the people **or** their court.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/colony_ledger.gd` | projection, filters, readings, rule copy |
| `scripts/map/map_play_colonies.gd` | both charts and the crown's record |
| `scripts/map/map_play_colony_pick.gd` | the court's own chain, worded |
| `scripts/ui/colony_ledger_panel.gd` | the sheet |
| `scripts/ui/colony_ledger_row.gd` | one colony |
| `scripts/ui/diplomacy_panel.gd` | the `COLONIES ›` door |

No figure is recomputed: the suzerain is `DiplomacyState.colony_of`, the subsidy
`DiplomacyState.subsidy`, the step `DiplomacyCatalog.BOYCOTT_TERMS`, the bar the
same boycott keys (`REQ-P2-03`).

## Tests

`tests/test_ledgers.gd` — the projection over a two-chart fixture, a sealed
colony with its subsidy, the filters and tallies, both row shapes, the court's
own chain and its gates, and the door, Visit and back.
