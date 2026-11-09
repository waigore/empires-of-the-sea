# Civilian units

Land units that explore, survey, improve and buy land. Starting three plus
tech-gated Merchant and Rail Builder; Spy is blocked.

**Pillars:** P2, P3, P1 (map feedback), P4.

**Wiki:** [civilian-units](https://github.com/waigore/empires-of-the-sea/wiki/civilian-units),
[extraction-and-improvements](https://github.com/waigore/empires-of-the-sea/wiki/extraction-and-improvements),
[fog-and-exploration](https://github.com/waigore/empires-of-the-sea/wiki/fog-and-exploration).

## Implemented

- **Roster** (`CivilianCatalog`): all six wiki types.
- **Playable:** Explorer (explore, prospect), Builder (improve), Engineer (road,
  port), Merchant (buy land), Rail Builder (railroad). Training at the capital
  spends treasury + paper, gated by Merchant Companies or Early Steam Engine.
- **Movement:** one orthogonal land tile per turn; Builders, Engineers and Rail
  Builders stay on crown land, while Merchants may cross Minor/Tribe provinces.
- **Work orders** target the unit's tile or, for a Builder, any owned resource
  tile; the unit records origin/assigned tiles and returns on cancel. Costs are
  paid at assign and not refunded. Explore ≤3 turns, prospect 1,
  improvement 1–4 (lumber + cast iron), road 1+1 (level 2 needs Road
  Construction), port 5+5 (2 turns), rail 2 lumber + 2 steel (2 turns, road 1–2
  → 4), fort 1–3 ([forts.md](forts.md)).
- **Overseas colonist** (`CivilianVoyage`): a civilian boards a crown squadron
  in port (one per hull, never with troops), sails, and goes ashore in the port
  province or on a coastal tile beside its zone. Explorers and Merchants may land
  on any coast; other types need crown land. Landing reveals the tile and its
  neighbours; a sunk squadron drowns its passengers.
- **Land purchase:** a Merchant buys a Minor/Tribe resource tile with an embassy,
  no war and a prospected mineral; 15× base price validated at assign, debited
  on completion. One deed per tile.
- **Tile deeds** (`TileOwnership`): deeds count as the buyer's land for works,
  yield, estates, fog, borders and saves; the province stays with the seller.
- **Improvements** yield `min(level, tech cap, transport, town)` when connected
  by road/port/town; upgrades above the tech cap are refused. `ESTATES` lists
  yield, blockers and Build / Cancel / Map.

## Deferred (REQ-P2-02)

- **Spy** — needs rival spies and AI activity; presence reveal ships.
- `upgrade_town` (town connectivity), rival civilian AI.
- Transport caps, raw → manufactured production, riches conversion.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/civilian_*.gd` | roster, state, movement, work, transport, voyage |
| `scripts/rules/land_purchase.gd`, `scripts/world/tile_ownership.gd` | merchant deeds |
| `scripts/rules/land_works.gd`, `improvement_*.gd` | tile works, connectivity, extraction, ledger |
| `scripts/map/civilian_layer.gd`, `civilian_voyage_map.gd` | markers, orders, passengers |
| `scripts/ui/civilian_panel.gd`, `improvement_panel.gd` | dossier and estates ledger |
| `scripts/map_screen.gd` | intents, training, end-of-turn wiring |

Rules stay node-free (`REQ-P3-03`).

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Select | click medallion | tap medallion |
| March | click glowing neighbour tile | tap glowing neighbour tile |
| Work order | dossier button | dossier button |
| Embark / land | fleet dossier **PASSENGERS** | same |
| Estates ledger | `ESTATES` / province **Build Improvement** | same |
| Cancel / close | dossier / ledger Close | dossier / ledger Close |

## Tests

`test_civilian_catalog`, `test_civilian_movement`, `test_civilian_work`,
`test_civilian_voyage`, `test_improvement_system`,
`test_map_screen_crown_orders`, `test_map_model`.

```bash
gd-tools test --coverage --min 80
```
