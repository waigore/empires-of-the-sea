# Civilian units

Land units that explore, survey, improve, colonize and spy.

**Pillars:** P1–P5.

**Wiki:** [civilian-units](https://github.com/waigore/empires-of-the-sea/wiki/civilian-units),
[extraction-and-improvements](https://github.com/waigore/empires-of-the-sea/wiki/extraction-and-improvements),
[fog-and-exploration](https://github.com/waigore/empires-of-the-sea/wiki/fog-and-exploration).

## Implemented

- **Roster** (`CivilianCatalog`): six wiki types; playable: Explorer (explore,
  prospect), Builder (improve, upgrade town), Engineer (road, port), Spy
  (passive), Merchant (buy land), Rail Builder (railroad).
- **Empire ledger** (`CivilianRosterPanel`): CREW chip or `C` lists every crew
  in both worlds, filtered by region/craft.
- **Movement:** one orthogonal land tile per turn; Builders, Engineers and Rail
  Builders keep to crown land; Explorer, Merchant and Spy cross any border.
- **Spy** (`SpyNetworks`): no work order. Holds its province charted (never
  `unknown`); each shadowed rival Great Power adds +15% RP to a Low+ slot on a
  tech that court knows, added to Industrial Funding before one floor.
- **Court reports** (`CourtReports`): a Spy that ends the turn on a rival's
  land earns a despatch under that court's chronicle — its acts, battles and
  captures, technologies finished. Names mask against your contacts; last turn
  only, in memory (DR-20261110-07).
- **Work orders** on the unit tile (Builders: any owned resource tile); cancel
  returns to origin. Explore ≤3, prospect 1, improvement 1–4 (lumber + cast
  iron), **upgrade town** (National Bureaucracy), road, port, rail, fort 1–3
  ([forts.md](forts.md)).
- **Town development:** Builder raises towns to level 4; connected port towns
  cap extraction; levels 2 and 4 add manufacturing ([economy.md](economy.md)).
- **Overseas colonist** (`CivilianVoyage`): boards a crown squadron in port
  (one per hull, never with troops), landing at the port province or a coastal
  tile beside its zone; Explorers/Merchants anywhere, others on crown land.
  Sunk ships drown passengers.
- **Land purchase:** Merchant buys a Minor/Tribe resource tile with embassy, no
  war and a prospected mineral; 15× base price, debited on completion.
- **Tile deeds** (`TileOwnership`): the buyer's land for works, yield, estates,
  fog, borders and saves; the province stays with the seller.
- **Improvements** yield `min(level, tech, terrain, transport, town)` when
  connected; over-cap upgrades are refused; `ESTATES` lists yield and orders.
- **Presence** keeps a province visible; one crew per tile.

## Deferred (REQ-P2-02)

- **Counter-spy** — needs rival spies to hunt.
- Rival civilian AI; Minor/Tribe town manufacturing offers.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/civilian_*.gd` | roster, state, movement, work, transport, voyage |
| `scripts/rules/spy_networks.gd` | spy hosts and research bonus |
| `scripts/rules/court_reports.gd` | despatch facts, masking, cap |
| `scripts/ui/court_reports_panel.gd` | the despatch block |
| `scripts/rules/land_purchase.gd`, `scripts/world/tile_ownership.gd` | deeds |
| `scripts/rules/land_works.gd`, `improvement_*.gd` | works, extraction, ledger |
| `scripts/map/civilian_*.gd`, `map_play_civilian_roster.gd` | markers, passengers, roster jump |
| `scripts/ui/civilian_*.gd`, `improvement_panel.gd` | dossier, roster, estates |

Rules stay node-free (`REQ-P3-03`).

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Select | click medallion | tap medallion |
| March | click glowing neighbour | tap glowing neighbour |
| Work order | dossier button | dossier button |
| Embark / land | fleet **PASSENGERS** | same |
| Estates | `ESTATES` | same |

## Tests

`test_civilian_field_rules`, `test_civilian_voyage`, `test_spy_networks`,
`test_court_reports`, `test_visibility`, `test_map_screen_crown_orders`.

```bash
gd-tools test --coverage --min 80
```
