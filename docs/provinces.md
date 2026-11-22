# The crown's realm

Every province the crown holds, both charts: yields (**Economy**), how hard it
holds (**Defence**), distance from the seat (**Connectivity**).

**Pillars:** P1 chrome, P2 the rules' reading, P3 pure projection, P5 one
place for the bookkeeping.

**Wiki:** [world-model](https://github.com/waigore/empires-of-the-sea/wiki/world-model)
§ Provinces and Tiles. Decisions: DR-20261115-09, DR-20261121-21.

## Opening it

**Realm** seals the bar (`T`) and the dossier's foot — the muster roll's
sibling, same chrome and pause park ([`armies.md`](armies.md)). The chart
switch (**OLD** / **NEW**) sits top-left.

## The three views

| View | Row reads | Ordered by |
|------|-----------|------------|
| Economy | estates, developed, room, gathered, value at today's sell | total value, or one kind |
| Defence | garrison × terrain + guns, with fort, ward and ground | the figure, highest first |
| Connectivity | hops from the seat, the crown road | hops, near first; no-road last |

Output is the harvest at **today's sell** (`WorldMarket.sell_price`), so no row
invents a price. Defence is the battle's own terms — `side_strength` ×
`ArmyModifiers.TERRAIN_DEFENCE` + `FortRules.emplaced_strength` — no second
formula (`REQ-P2-03`). Towns, walls and hospitals ride these views; the
dossier raises each ([`towns.md`](towns.md), [`walls.md`](walls.md),
[`hospitals.md`](hospitals.md)).

## Filters

Three chip rows — **chart**, **view**, **order** — a count line of cut-off,
ungarrisoned and at-works tallies, and **Visit**.

## The court's own orders here

Under the head one gold line names what the court would do here: the work its
civilian pass would give crews and the hosts its land pass would send —
`The court would order its Builder to raise the lumber camp and the field army
at Tucapel to storm Cádiz this turn.` An idle crew earns the gate instead
(DR-20261121-19). The rail's presses wear the same read: the raise it names
leads with **▸**; the legend says so (DR-20261122-23).

## Across the realm

The sheet's gold line names the provinces the court would act in —
`The court would act in 3 of its 14 provinces this turn — Cádiz, Tucapel and
Jaén.` — and every such row leads with **▸**. Both passes are asked once for
the realm. Neither line orders anything: no work, march, spend, save key or
turn moves.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/province_ledger.gd` | assembly, views, orders |
| `scripts/rules/realm_readings.gd` | the three figures |
| `scripts/map/map_play_provinces.gd` | the two charts' assembly, `Visit` |
| `scripts/map/map_play_province_counsel.gd` | the court reading |
| `scripts/map/map_play_realm_counsel.gd` | the realm's court reading |
| `scripts/ui/province_ledger_panel.gd` | the sheet |
| `scripts/ui/province_ledger_row.gd` | one province per view |
| `scripts/ui/province_panel.gd` | the dossier and its reading |
| `scripts/ui/press_marks.gd` | press captions and marks |

## Tests

`tests/test_ledgers.gd` — projection, views, both readings, marks, door,
Visit, back, key.

## The dossier's facts

A tap opens the province: ground, harbour, town level, roads, fort, **Wall**
(what it soaks and spares, DR-20261120-06), hospital and **Deeds**. Wall and
Deeds hide when empty. A Tribe shore with another crown's deed refuses an
undeclared march in those words (`DeedBar`, DR-20261120-05).