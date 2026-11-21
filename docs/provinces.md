# The crown's realm

Every province the crown holds, in both charts, one sheet read three ways —
what it yields (**Economy**), how hard it is to hold (**Defence**) and how far
it sits from the seat (**Connectivity**).

**Pillars:** P1 (chrome on the map), P2 (the reading is the rules'), P3 (pure
projection), P5 (one place for the bookkeeping).

**Wiki:** [world-model](https://github.com/waigore/empires-of-the-sea/wiki/world-model)
§ Provinces and Tiles; [capital-and-connectivity](https://github.com/waigore/empires-of-the-sea/wiki/capital-and-connectivity)
§ Connectivity. Decision: DR-20261115-09.

## Opening it

The bar's first seal is **Realm** (`T`), left of **LENS** and **CAPITAL**; the
dossier's foot carries **Realm** too. It is the muster roll's sibling: same
chrome and pause park ([`armies.md`](armies.md)). The chart switch
(**OLD** / **NEW**) sits on the map's top-left corner; a one-chart world offers
no press.

## The three views

| View | Row reads | Ordered by |
|------|-----------|------------|
| Economy | estates, developed, room, gathered, value at today's sell | total value, or one kind |
| Defence | garrison × terrain + guns, with fort, ward and ground | the figure, highest first |
| Connectivity | hops from the seat, the crown road | hops, near first; no-road last |

Output is the harvest at **today's sell** (`WorldMarket.sell_price`), so a row
never invents a price. Defence is the battle's own terms: `side_strength` ×
`ArmyModifiers.TERRAIN_DEFENCE` + `FortRules.emplaced_strength` — no second
combat formula (`REQ-P2-03`).

Towns, walls and hospitals ride these views; the dossier's order raises each
([`towns.md`](towns.md), [`walls.md`](walls.md), [`hospitals.md`](hospitals.md)).

## Filters

Three chip rows — **chart**, **view**, **order** — with a count line of the
cut-off, ungarrisoned and at-works tallies. **Visit** frames the province and
opens its dossier.

## What it never does

No order, work, march, spend, save key or turn moves: the rows are a reading.

## The court's own orders here

Under the head, one gold line names what the court would do here this turn:
the work its civilian pass would put crews to and the hosts its land pass would
send — `The court would order its Builder to raise the lumber camp and the
field army at Tucapel to storm Cádiz this turn.` An idle crew here earns the
gate instead. A reading; nothing is ordered (DR-20261121-19).

## Architecture

| File | Role |
|------|------|
| `scripts/rules/province_ledger.gd` | assembly, views, orders |
| `scripts/rules/realm_readings.gd` | the three figures |
| `scripts/map/map_play_provinces.gd` | the two charts' assembly, `Visit` |
| `scripts/map/map_play_province_counsel.gd` | the court reading |
| `scripts/ui/province_ledger_panel.gd` | the sheet |
| `scripts/ui/province_ledger_row.gd` | one province per view |
| `scripts/ui/province_panel.gd` | the dossier and its reading |

## Tests

`tests/test_ledgers.gd` — the projection, views, the dossier's links and
reading, the door, Visit, back and key.

## The dossier's facts

A tap opens the province: the ground a battle fights on, the harbour, town
level, roads, fort, **Wall** (what it soaks and spares, DR-20261120-06),
hospital and **Deeds** — the crowns that bought land here. Wall and Deeds hide
when empty. A Tribe shore with another crown's deed refuses an undeclared march
in those words (`DeedBar`, DR-20261120-05).