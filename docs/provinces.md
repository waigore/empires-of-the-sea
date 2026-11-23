# The crown's realm

Both charts: yields (**Economy**), how hard it holds (**Defence**), the seat's
distance (**Connectivity**).

**Pillars:** P1 chrome, P2 the rules' reading, P3 pure projection, P5 one
place for the bookkeeping.

**Wiki:** [world-model](https://github.com/waigore/empires-of-the-sea/wiki/world-model)
§ Provinces and Tiles. Decisions: DR-20261115-09, DR-20261121-21.

## Opening it

**Realm** seals the bar (`T`) and the dossier's foot — the muster roll's
sibling, same chrome ([`armies.md`](armies.md)). Chart switch
**OLD** / **NEW** top-left.

## The three views

| View | Row reads | Ordered by |
|------|-----------|------------|
| Economy | estates, developed, room, gathered, value at today's sell | total value, or one kind |
| Defence | garrison × terrain + guns, with fort, ward and ground | the figure, highest first |
| Connectivity | hops from the seat, the crown road | hops, near first; no-road last |

Output is the harvest at **today's sell** (`WorldMarket.sell_price`), so no row
invents a price. Defence is the battle's own terms (`side_strength` × terrain
+ guns); no second formula (`REQ-P2-03`). Towns, walls and hospitals ride them; the dossier raises each
([`towns.md`](towns.md), [`walls.md`](walls.md), [`hospitals.md`](hospitals.md)).

## Filters

Three chip rows — **chart**, **view**, **order** — a count line of cut-off,
ungarrisoned and at-works tallies, and **Visit**.

## The court's own orders here

One gold line names what the court would do here: its civilian pass's work and
its land pass's hosts; an idle crew earns the gate (DR-20261121-19). The rail's
named raise leads with **▸** (DR-20261122-23).

## Across the realm

The gold line names the provinces the court would act in — `The court would act
in 3 of its 14 provinces this turn — Cádiz, Tucapel and Jaén.` Every such row
leads with **▸**; both passes are asked once. Neither line orders anything.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/province_ledger.gd` | assembly, views, orders |
| `scripts/rules/realm_readings.gd` | the three figures |
| `scripts/map/map_play_provinces.gd` | the two charts' assembly, `Visit` |
| `scripts/map/map_play_province_counsel.gd` | the court reading |
| `scripts/map/map_play_realm_counsel.gd` | the realm's court reading |
| `scripts/rules/province_hosts.gd` | the Hosts count |
| `scripts/map/map_play_province_hosts.gd` | its session bind |
| `scripts/rules/province_harbour.gd` | the Squadrons count |
| `scripts/map/map_play_province_harbour.gd` | its session read |
| `scripts/ui/province_ledger_panel.gd` | the sheet |
| `scripts/ui/province_ledger_row.gd` | one province per view |
| `scripts/ui/province_panel.gd` | the dossier and its reading |
| `scripts/ui/province_orders_section.gd` | the order rail |
| `scripts/ui/province_raise_presses.gd` | town, wall and ward presses |
| `scripts/ui/province_muster_block.gd` | craft rows and the hire line |
| `scripts/ui/press_marks.gd` | press captions and marks |

## Tests

`tests/test_ledgers.gd` — projection, views, both readings, marks, door,
Visit, back and key.

## The dossier's facts

A tap opens the province: ground, harbour, town, roads, fort, **Wall**
(DR-20261120-06) — soaks, spares and storm (DR-20261123-20) — **Hosts**
(DR-20261123-13), **Squadrons** — the hulls in the harbour, the same fog gate
(DR-20261123-14) — hospital and **Deeds**; empty rows hide. A Tribe shore with
another crown's deed refuses an undeclared march in those words (`DeedBar`,
DR-20261120-05).

## Deferred (REQ-P2-02)

None — [`deferred.md`](deferred.md).
