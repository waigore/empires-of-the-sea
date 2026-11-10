# Civilian units

Land units that explore, survey, improve, colonize and spy; four start, two
unlock by tech.

**Pillars:** P1–P5.

**Wiki:** [civilian-units](https://github.com/waigore/empires-of-the-sea/wiki/civilian-units),
[extraction-and-improvements](https://github.com/waigore/empires-of-the-sea/wiki/extraction-and-improvements),
[fog-and-exploration](https://github.com/waigore/empires-of-the-sea/wiki/fog-and-exploration).

## Implemented

- **Roster** (`CivilianCatalog`): six wiki types; playable Explorer, Builder,
  Engineer, Spy (passive), Merchant, Rail Builder. Capital training spends
  treasury + paper.
- **Empire ledger** (`CivilianRosterPanel`): CREW/`C` lists every crew; filter
  by region/craft; Visit jumps to it.
- **Movement:** one orthogonal land tile/turn; Builders, Engineers, Rail
  Builders stay on crown land; Explorer, Merchant, Spy cross any border.
- **Spy** (`SpyNetworks`): no work order. Holds its province charted; each
  shadowed rival GP adds +15% RP to a Low+ slot court knows, before one floor.
- **Work orders** on the unit tile (Builders: any owned resource tile); cancel
  returns to origin. Explore ≤3, prospect 1, improve 1–4 (lumber + cast iron),
  **upgrade town** (same costs, National Bureaucracy), road, port, rail, fort
  1–3 ([forts.md](forts.md)).
- **Town development:** Builder raises towns to level 4; connected port towns
  cap extraction; levels 2 and 4 add manufacturing ([economy.md](economy.md)).
- **Overseas colonist** (`CivilianVoyage`): boards a crown squadron in port
  (one per hull, never with troops); lands at port province or coastal tile
  beside its zone. Explorers/Merchants any coast; others need crown land.
  Landing reveals tile + neighbours; sunk ships drown passengers.
- **Land purchase:** Merchant buys Minor/Tribe resource tile with embassy, no
  war, prospected mineral; 15× base at assign, debit on complete.
- **Tile deeds** (`TileOwnership`): buyer's land for works, yield, estates, fog,
  borders, saves; province stays with the seller.
- **Improvements** yield `min(level, tech, terrain, transport, town)` when
  connected; above-cap upgrades refused; `ESTATES` lists yield and orders.
- **Presence** keeps a province visible; one crew per tile per crown (Rail
  Builders exempt).
- **Stranding:** crews caught by conquest withdraw to crown land or are lost;
  a fallen crown's crews leave play.

## Deferred (REQ-P2-02)

- **Counter-spy** and court reports — need rival spies and a digest spec.
- Rival civilian AI; Minor/Tribe town manufacturing offers.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/civilian_*.gd` | roster, state, movement, work, transport, voyage |
| `scripts/rules/spy_networks.gd` | spy hosts and research bonus |
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
| Empire roster | CREW/`C`; Visit | same |
| Embark / land | fleet **PASSENGERS** | same |
| Estates | `ESTATES` / province Build | same |
| Cancel / close | dossier / ledger Close | same |

## Tests

`test_civilian_field_rules`, `test_civilian_voyage`, `test_spy_networks`,
`test_visibility`, `test_map_screen_crown_orders`.

```bash
gd-tools test --coverage --min 80
```
