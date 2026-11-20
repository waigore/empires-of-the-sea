# The crown's realm

Every province the crown holds, in both charts, in one sheet read three ways —
what it yields (**Economy**), how hard it is to hold (**Defence**) and how far
it sits from the seat (**Connectivity**).

**Pillars:** P1 (chrome on the map), P2 (the reading is the rules'), P3 (pure
projection), P5 (one place for the turn's bookkeeping).

**Wiki:** [world-model](https://github.com/waigore/empires-of-the-sea/wiki/world-model)
§ Provinces and Tiles; [capital-and-connectivity](https://github.com/waigore/empires-of-the-sea/wiki/capital-and-connectivity)
§ Connectivity. Decision: DR-20261115-09.

## Opening it

The bar's first command seal is **Realm** (`T`), left of **LENS** and
**CAPITAL**; the province dossier's foot carries **Realm** as a second door. The
sheet is the muster roll's sibling: its own modal layer, the same chrome, the
same pause-door park ([`armies.md`](armies.md) § the muster roll).

The chart switch (**OLD** / **NEW**) sits on the map's own top-left corner, not
the bar. A one-chart world keeps the pill as context and offers no press.

## The three views

| View | Row reads | Ordered by |
|------|-----------|------------|
| Economy | estates, developed, room to raise, units gathered, value at today's sell, the kinds it gathers | total value, or one kind (timber / ore / riches / farm) |
| Defence | one figure — garrison × terrain + emplaced guns — with fort, ward and the ground it fights on | the figure, highest first |
| Connectivity | hops from the seat over owned land, the crown road, the chart of the seat | hops, near first; no-road provinces last |

Economic output is the estate harvest priced at **today's sell** — the same
`WorldMarket.sell_price` the market ledger clears at, so a realm row never
invents a price. The defence figure is the battle's own terms:
`ArmyForce.side_strength` × `ArmyModifiers.TERRAIN_DEFENCE` +
`FortRules.emplaced_strength`. No second combat formula lives here
(`REQ-P2-03`).

Towns, walls and hospitals are carried by these views now; the separate
town / wall / hospital sheets are gone. The step that raises one is the province
dossier's own order ([`towns.md`](towns.md), [`walls.md`](walls.md),
[`hospitals.md`](hospitals.md)).

## Filters

Three chip rows — **chart** (both / Old World / New World), **view**, and
**order** — with the count line naming the cut-off, ungarrisoned and at-works
tallies. **Visit** frames the province and opens the dossier a tap would open.

## What it never does

No order, work, march, spend, save key or turn moves. Opening it changes
nothing; the rows are a reading.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/province_ledger.gd` | assembly, views, orders, row copy |
| `scripts/rules/realm_readings.gd` | economy, defence and connectivity figures |
| `scripts/map/map_play_provinces.gd` | the two charts' assembly, `Visit` |
| `scripts/ui/province_ledger_panel.gd` | the sheet |
| `scripts/ui/province_ledger_row.gd` | one province, one view |
| `scripts/ui/map_region_toggle.gd` | the chart pill on the map |
| `scripts/ui/province_panel.gd` | the dossier's `Realm` door |

## Tests

`tests/test_ledgers.gd` — the projection over both charts, the three views, the
sort orders, the dossier's link readings, and the door, Visit, back and key.

## The dossier's facts

A tap on a province opens its sheet: the ground a battle here fights on, the
harbour, the town level, the roads, the fort, **Wall** (what it soaks and the
share of a blow it spares, DR-20261120-06), the hospital — and **Deeds**, the
crowns that have bought land in it. Wall and Deeds hide when they have nothing
to say. A Tribe shore with another crown's deed refuses an undeclared march in
those words (`DeedBar`, DR-20261120-05).
