# The crown's realm

Every province the crown holds, in both charts, one sheet read three ways —
what it yields (**Economy**), how hard it is to hold (**Defence**) and how far
it sits from the seat (**Connectivity**).

**Pillars:** P1 chrome, P2 the rules' reading, P3 pure projection, P5 one place
for the bookkeeping.

**Wiki:** [world-model](https://github.com/waigore/empires-of-the-sea/wiki/world-model)
§ Provinces and Tiles. Decisions: DR-20261115-09, DR-20261121-21.

## Opening it

The bar's first seal is **Realm** (`T`); the dossier's foot carries **Realm**
too — the muster roll's sibling, same chrome and pause park
([`armies.md`](armies.md)). The chart switch (**OLD** / **NEW**) sits top-left.

## The three views

| View | Row reads | Ordered by |
|------|-----------|------------|
| Economy | estates, developed, room, gathered, value at today's sell | total value, or one kind |
| Defence | garrison × terrain + guns, with fort, ward and ground | the figure, highest first |
| Connectivity | hops from the seat, the crown road | hops, near first; no-road last |

Output is the harvest at **today's sell** (`WorldMarket.sell_price`), so a row
never invents a price. Defence is the battle's own terms: `side_strength` ×
`ArmyModifiers.TERRAIN_DEFENCE` + `FortRules.emplaced_strength` — no second
formula (`REQ-P2-03`). Towns, walls and hospitals ride these views; the
dossier's order raises each ([`towns.md`](towns.md), [`walls.md`](walls.md),
[`hospitals.md`](hospitals.md)).

## Filters

Three chip rows — **chart**, **view**, **order** — a count line of the cut-off,
ungarrisoned and at-works tallies, and **Visit**.

## The court's own orders here

Under the head, one gold line names what the court would do here this turn: the
work its civilian pass would put crews to and the hosts its land pass would
send — `The court would order its Builder to raise the lumber camp and the
field army at Tucapel to storm Cádiz this turn.` An idle crew here earns the
gate instead (DR-20261121-19).

## Across the realm

The sheet's own gold line names the provinces the court would act in —
`The court would act in 3 of its 14 provinces this turn — Cádiz, Tucapel and
Jaén.` — and every such row leads with **▸**. Both passes are asked once for
the whole realm. Neither line orders anything: no work, march, spend, save key
or turn moves.

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

## Tests

`tests/test_ledgers.gd` — projection, views, both readings, door, Visit, back,
key.

## The dossier's facts

A tap opens the province: ground, harbour, town level, roads, fort, **Wall**
(what it soaks and spares, DR-20261120-06), hospital and **Deeds**. Wall and
Deeds hide when empty. A Tribe shore with another crown's deed refuses an
undeclared march in those words (`DeedBar`, DR-20261120-05).