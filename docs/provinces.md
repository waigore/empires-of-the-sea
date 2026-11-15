# The crown's provinces

Every province the crown holds, in both charts, in one ledger — what each one
yields, who holds it, and what it lacks.

**Pillars:** P1 (setup chrome), P2 (the reading is the rules'), P3 (pure
projection), P5 (one place for the turn's bookkeeping).

**Wiki:** [world-model](https://github.com/waigore/empires-of-the-sea/wiki/world-model)
§ Provinces and Tiles; [capital-and-connectivity](https://github.com/waigore/empires-of-the-sea/wiki/capital-and-connectivity)
§ Connectivity. Decision: DR-20261115-09.

## Opening it

The province dossier's foot carries **Realm** (`T`). The ledger is the muster
roll's sibling: its own modal layer, the same sheet chrome, the same pause-door
park ([`armies.md`](armies.md) § the muster roll). The cartouche is full — a
seal there would take the desktop bar to a second row — so the door lives where
a crown asks about its land.

## What a row reads

| Line | Reads |
|------|-------|
| Place | the harbour's own water (`Harbour — Mar Caribe`), else `Inland` |
| Built | town level, fort, hospital, estates and their yield a turn |
| Held | regiments and `ArmyForce.side_strength` of the crown's armies there |
| Link | `Roads to the seat`, `Harbour blockaded`, `Cut off — n road tiles to lay` |

The chip names the worst thing first: `SEAT`, `CUT OFF`, `UNGARRISONED`,
`WORKS`, `HELD`.

## Filters

Two chip rows — **chart** (both / Old World / New World) and **reading** (all /
cut off / ungarrisoned / works) — each carrying its own tally, so a zero stays
legible. **Visit** frames the province and opens the dossier a tap would open.

## What it never does

No order, work, march, spend, save key or turn moves. Opening it changes
nothing; the rows are a reading.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/province_ledger.gd` | projection, filters, row copy |
| `scripts/map/map_play_provinces.gd` | the two charts' assembly, `Visit` |
| `scripts/ui/province_ledger_panel.gd` | the sheet |
| `scripts/ui/province_ledger_row.gd` | one province |
| `scripts/ui/province_panel.gd` | the `Realm` door |

No number is recomputed: the yield is `ImprovementLedger`'s own `output` and the
garrison is the resolver's own strength (`REQ-P2-03`).

## Tests

`tests/test_ledgers.gd` — the province ledger projection over both charts, the flags and
their tallies, the dossier's link readings, and the door, Visit, back and key.
