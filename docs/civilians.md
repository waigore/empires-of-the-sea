# Civilian units

Land units that explore, survey, improve and buy land. Spy is catalogued but
blocked.

**Pillars:** P2, P3 (rules/view), P1 (map feedback), P4 (turn-based).

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
  tile. Costs are paid at assign and not refunded. Explore ≤3 turns, prospect 1,
  improvement 1–4 (1/4/8/16 lumber + cast iron), road 1+1 (level 2 needs Road
  Construction), port 5+5 (2 turns), rail 2 lumber + 2 steel (2 turns, road 1–2
  → 4), fort 1–3 ([forts.md](forts.md)).
- **Land purchase:** a Merchant buys a Minor/Tribe resource tile with an embassy,
  no war and a prospected mineral; 15× base price validated at assign, debited
  on completion. One deed per tile.
- **Tile deeds** (`TileOwnership`): purchased tiles count as the buyer's land for
  improvements, extraction, estates, visibility, borders and saves, while the
  province stays with the seller.
- **Improvements** are named from the resource (Farm, Lumber camp, Mine, Pasture,
  Ranch) and yield `min(level, tech cap, transport, town)` when connected by
  road/port/town; upgrades above the tech cap are refused. The `ESTATES` ledger
  lists realm yield, blockers and Build / Cancel / Map.
- **Presence** keeps a province visible; one crew per tile per crown (Rail
  Builders exempt).
- **Stranding:** crews caught by a conquered province withdraw to crown land or
  are lost; a fallen crown's crews leave play.

## Deferred (REQ-P2-02)

- **Spy** — counter-spy and court reports need rival spies and research;
  presence reveal already ships.
- Civilian overseas deployment and cargo for New World yield.
- `upgrade_town` (town connectivity).
- Transport caps, raw → manufactured production, riches conversion.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/civilian_*.gd` | roster, state, movement, work validation |
| `scripts/rules/land_purchase.gd`, `scripts/world/tile_ownership.gd` | merchant deeds |
| `scripts/rules/civilian_transport.gd` | roads, improved road, port, rail |
| `scripts/rules/land_works.gd`, `improvement_*.gd` | tile works, connectivity, extraction, ledger |
| `scripts/map/civilian_layer.gd` | markers, orders, development drawing |
| `scripts/ui/civilian_panel.gd`, `improvement_panel.gd` | dossier and estates ledger |
| `scripts/map_screen.gd` | intents, training, end-of-turn wiring |

Rules stay node-free (`REQ-P3-03`); panel → `CivilianWork.assign`, movement →
`CivilianMovement`, estates → `ImprovementOrders`.

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Select | click medallion | tap medallion |
| March | click glowing neighbour tile | tap glowing neighbour tile |
| Work order | dossier button | dossier button |
| Estates ledger | `ESTATES` / province **Build Improvement** | same |
| Cancel / close | dossier / ledger Close | dossier / ledger Close |

## Tests

`test_civilian_catalog`, `test_civilian_movement`, `test_civilian_work`,
`test_improvement_system`, `test_map_screen_crown_orders`, `test_map_model`.

```bash
gd-tools test --coverage --min 80
```
