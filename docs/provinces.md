# The crown's realm

Both charts: yields (**Economy**), holds (**Defence**), the seat's distance
(**Connectivity**).

**Pillars:** P1 chrome, P2 the rules' reading, P3 pure projection, P5 one
place for bookkeeping.

**Wiki:** [world-model](https://github.com/waigore/empires-of-the-sea/wiki/world-model)
§ Provinces and Tiles. Decisions: DR-20261115-09, DR-20261121-21,
DR-20261123-25.

## Opening it

**Realm** seals the bar (`T`) and the dossier's foot — the muster roll's sibling
([`armies.md`](armies.md)). Chart switch **OLD** / **NEW**.

## The three views

| View | Row reads | Ordered by |
|------|-----------|------------|
| Economy | estates, developed, room, gathered, value at today's sell | total value, or one kind |
| Defence | garrison × terrain + guns, with fort, ward and ground | the figure, highest first |
| Connectivity | hops from the seat, the crown road | hops, near first; no-road last |

Output is the harvest at **today's sell** (`WorldMarket.sell_price`), so no row
invents a price; Defence is the battle's own terms (`side_strength` × terrain
+ guns), no second formula (`REQ-P2-03`). Towns, walls and wards ride them; the
dossier raises each ([`towns.md`](towns.md), [`walls.md`](walls.md),
[`hospitals.md`](hospitals.md)).

## Filters

Three chip rows — **chart**, **view**, **order** — a cut-off, ungarrisoned and
at-works count, plus **Visit**.

## The court's own orders here

One gold line names the civilian work and land hosts here; an idle crew earns
the gate (DR-20261121-19). The rail's raise leads with **▸** (DR-20261122-23).

## Across the realm

The gold line names the provinces the court would act in — `The court would act
in 3 of its 14 provinces this turn — Cádiz, Tucapel and Jaén.` Each row leads
with **▸**. Neither line orders anything.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/province_ledger.gd`, `realm_readings.gd` | assembly, the three figures |
| `scripts/map/map_play_provinces.gd` | both charts' assembly, `Visit` |
| `scripts/map/map_play_province_counsel.gd`, `map_play_realm_counsel.gd` | the court readings, here and across the realm |
| `scripts/rules/province_hosts.gd`, `scripts/map/map_play_province_hosts.gd` | the Hosts count and its bind |
| `scripts/rules/province_harbour.gd`, `scripts/map/map_play_province_harbour.gd` | the Squadrons count and its read |
| `scripts/ui/province_ledger_panel.gd`, `province_ledger_row.gd` | the sheet and one row per view |
| `scripts/ui/province_panel.gd`, `province_sheet_shell.gd`, `province_resources.gd`, `scripts/map/map_play_province_harvest.gd` | the dossier, its frame, its estate block, the harvest |
| `scripts/ui/province_orders_section.gd`, `province_raise_presses.gd`, `province_muster_block.gd`, `press_marks.gd` | the rail, presses, craft rows, marks |

## Tests

`tests/test_ledgers.gd` — projection, views, readings, marks, door, Visit, back
and key.

## The dossier's facts

A tap opens the province: ground, **Port**, town, roads, fort, **Wall** — soaks,
spares, storm (DR-20261120-06, DR-20261123-20) — **Hosts** (DR-20261123-13),
**Squadrons** — hulls and their regiments, same fog gate (DR-20261123-14,
DR-20261123-18) — hospital and **Deeds**; empty rows hide. The **Port** row reads
the harbour that stands: its `Transport 4`, the seal on a blockaded one, or a
bare coast's port price (DR-20261125-06). A Tribe's land needs a declaration
(DR-20261124-07); **Deeds** still names the courts that bought land there
(`DeedBar`) — the intervention trial's stake. Under its estate rows it prices the
**harvest** at today's sell and the room to raise — the realm's Economy reading
(DR-20261123-25); another crown's ground prints none.

## Deferred (REQ-P2-02)

None — [`deferred.md`](deferred.md).
