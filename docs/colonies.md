# The world's colonies

Every Tribe a Great Power has bought, in one ledger — who holds it, where it
stands and what that court's boycott shuts.

**Pillars:** P1 (period sheet), P2 (the record's own readings), P3 (pure
projection), P5 (one place for the boycott a crown issued).

**Wiki:** [diplomacy](https://github.com/waigore/empires-of-the-sea/wiki/diplomacy)
§ GP–Tribe Rules — Join Empire, § Boycott. Decision: DR-20261117-02.

## Opening it

The court ledger carries **COLONIES ›** beside **EYES ›**: a boycott is issued
from a court's page and read on the colony it shuts. No key — the letters are
spent.

## What a row reads

| Line | Reads |
|------|-------|
| Medallion | the globe: a people, not a province |
| Chip | `OURS`, `SEALED`, `PAYS`, `COLONY` |
| Name | the people's own name (`The Inca`) |
| Detail | `<capital> — colony of <court>`, then the chart |
| Standing | the herald's word with the people, and their subsidy |
| Reading | their provinces, and `Open to every court` or `Sealed to …` |

**Visit** frames the colony's capital and opens its dossier — a colony keeps its
land, so its seat is a place on the chart.

## Filters

Two chip rows — **chart** (both / Old World / New World) and **reading** (all /
our colonies / sealed / subsidised) — each with its own tally, so a zero stays
legible. The crown's own colonies lead, then the sealed, then by the court that
holds them; one heading per chart.

**The rule on the sheet:** a boycott shuts every colony of the issuer to the
boycotted court — no deal clears either way, its aid and deeds are refused, and
its terms worsen 10%. A colony keeps its provinces, its court and its trade;
only the Join Empire price was paid.

## What it never does

No deed, overture, boycott or lift is filed, and no save key moves: it is a
reading. The press stays on the court's own page.

## No row without an envoy

A people the crown has not met prints no row, the masking the chronicle uses
(`Unknown faction`). A colony prints when the crown knows the people **or** the
court that bought them: a public act between known courts is the crown's news.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/colony_ledger.gd` | projection, filters, readings, rule copy |
| `scripts/map/map_play_colonies.gd` | both charts and the crown's record |
| `scripts/ui/colony_ledger_panel.gd` | the sheet |
| `scripts/ui/colony_ledger_row.gd` | one colony |
| `scripts/ui/diplomacy_panel.gd` | the `COLONIES ›` door |

No figure is recomputed: the suzerain is `DiplomacyState.colony_of`, the subsidy
`DiplomacyState.subsidy`, the step `DiplomacyCatalog.BOYCOTT_TERMS`, and the bar
the same boycott keys `DiplomacyTrade` reads (`REQ-P2-03`).

## Tests

`tests/test_ledgers.gd` — the projection over a two-chart fixture, a sealed
colony with its subsidy, the filters and tallies, the unrecognised people, both
row shapes, and the door, Visit and back on the mounted map.
