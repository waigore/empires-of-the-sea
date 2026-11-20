# The crown's realm

Every province the crown holds, in both charts, in one sheet read three ways —
what it yields (**Economy**), how hard it is to hold (**Defence**) and how far
it sits from the seat (**Connectivity**).

**Pillars:** P1 (chrome on the map), P2 (the reading is the rules'), P3 (pure
projection), P5 (one place for the bookkeeping).

**Wiki:** [world-model](https://github.com/waigore/empires-of-the-sea/wiki/world-model)
§ Provinces and Tiles; [capital-and-connectivity](https://github.com/waigore/empires-of-the-sea/wiki/capital-and-connectivity)
§ Connectivity. Decision: DR-20261115-09.

## Opening it

The bar's first command seal is **Realm** (`T`), left of **LENS** and
**CAPITAL**; the province dossier's foot carries **Realm** as a second door. The
sheet is the muster roll's sibling: its own modal layer, the same chrome, the
same pause-door park ([`armies.md`](armies.md) § the muster roll).

The chart switch (**OLD** / **NEW**) sits on the map's top-left corner, not the
bar; a one-chart world keeps it as context and offers no press.

## The three views

| View | Row reads | Ordered by |
|------|-----------|------------|
| Economy | estates, developed, room to raise, units gathered, value at today's sell, kinds gathered | total value, or one kind (timber / ore / riches / farm) |
| Defence | one figure — garrison × terrain + emplaced guns — with fort, ward and ground | the figure, highest first |
| Connectivity | hops from the seat, the crown road, the seat's chart | hops, near first; no-road last |

Economic output is the harvest at **today's sell** (`WorldMarket.sell_price`),
so a row never invents a price. The defence figure is the battle's own terms:
`side_strength` × `ArmyModifiers.TERRAIN_DEFENCE` + `FortRules.emplaced_strength`
— no second combat formula (`REQ-P2-03`).

Towns, walls and hospitals ride these views now; their separate sheets are gone.
The step that raises one is the province dossier's order ([`towns.md`](towns.md),
[`walls.md`](walls.md), [`hospitals.md`](hospitals.md)).

## Filters

Three chip rows — **chart**, **view**, **order** — with a count line naming the
cut-off, ungarrisoned and at-works tallies. **Visit** frames the province and
opens its dossier.

## What it never does

No order, work, march, spend, save key or turn moves: the rows are a reading.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/province_ledger.gd` | assembly, views, orders, row copy |
| `scripts/rules/realm_readings.gd` | economy, defence and connectivity figures |
| `scripts/map/map_play_provinces.gd` | the two charts' assembly, `Visit` |
| `scripts/ui/province_ledger_panel.gd` | the sheet |
| `scripts/ui/province_ledger_row.gd` | one province per view |
| `scripts/ui/map_region_toggle.gd` | the chart pill on the map |
| `scripts/ui/province_panel.gd` | the dossier's `Realm` door |

## Tests

`tests/test_ledgers.gd` — the projection over both charts, the three views, the
orders, the dossier's link readings, and the door, Visit, back and key.

## The dossier's facts

A tap opens the province: the ground a battle here fights on, the harbour, town
level, roads, fort, **Wall** (what it soaks and spares, DR-20261120-06), hospital,
and **Deeds** — the crowns that have bought land in it. Wall and Deeds hide when
empty. A Tribe shore with another crown's deed refuses an undeclared march in
those words (`DeedBar`, DR-20261120-05).
