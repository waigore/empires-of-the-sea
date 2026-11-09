# Civilian units

Land units that explore, survey, improve and buy land. Three start; Merchant and
Rail Builder unlock by tech; Spy is catalogued but blocked.

**Pillars:** P2, P3, P1, P4, P5.

**Wiki:** [civilian-units](https://github.com/waigore/empires-of-the-sea/wiki/civilian-units),
[extraction-and-improvements](https://github.com/waigore/empires-of-the-sea/wiki/extraction-and-improvements),
[fog-and-exploration](https://github.com/waigore/empires-of-the-sea/wiki/fog-and-exploration).

## Implemented

- **Roster** (`CivilianCatalog`): all six wiki types; Explorer, Builder,
  Engineer, Merchant and Rail Builder are playable. Training at the capital
  costs treasury + paper, gated by Merchant Companies or Early Steam Engine.
- **Empire ledger** (`CivilianRosterPanel`): the CIVILIANS chip or `C` lists every
  crew in both worlds, filters by region and craft, and Visit jumps to its map
  and dossier.
- **Movement:** one orthogonal land tile per turn; Merchants may cross
  Minor/Tribe provinces, other types stay on crown land.
- **Work orders** target the unit's tile (Builders may take any owned resource
  tile); origin/assigned tiles are recorded and cancel moves the unit back.
  Costs are paid at assign and not refunded. Explore ≤3 turns, prospect 1,
  improvement 1–4 (1/4/8/16 lumber + cast iron), road 1+1 (level 2 needs Road
  Construction), port 5+5 (2 turns), rail 2 lumber + 2 steel (2 turns, road 1–2
  → 4), fort 1–3 ([forts.md](forts.md)).
- **Land purchase:** a Merchant buys a Minor/Tribe resource tile with an embassy,
  no war and a prospected mineral; 15× base price, charged on completion. One
  deed per tile.
- **Tile deeds** (`TileOwnership`): purchased tiles count as the buyer's land for
  improvements, estates, visibility, borders and saves; the province stays with
  the seller.
- **Improvements** are named from the resource and yield
  `min(level, tech cap, transport, town)` when connected; above-cap upgrades are
  refused. `ESTATES` lists yields, blockers and orders.
- **Presence** keeps a province visible; one crew per tile per crown (Rail
  Builders exempt).

## Deferred (REQ-P2-02)

- **Spy** — counter-spy and court reports need rival spies, research and AI
  activity.
- Overseas deployment/cargo, `upgrade_town`, rival civilian AI, transport caps,
  raw → manufactured production, riches conversion.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/civilian_*.gd` | roster, state, movement, work validation |
| `scripts/rules/land_purchase.gd`, `scripts/world/tile_ownership.gd` | merchant deeds |
| `scripts/rules/civilian_transport.gd` | roads, improved road, port, rail |
| `scripts/rules/land_works.gd`, `improvement_*.gd` | tile works, connectivity, extraction, ledger |
| `scripts/map/civilian_*.gd`, `map_play_civilian_roster.gd` | markers, orders, development, roster jump |
| `scripts/ui/civilian_*.gd` | dossier, estates ledger, roster panel |
| `scripts/map_screen.gd` | intents, training, end-of-turn wiring |

Rules stay node-free (`REQ-P3-03`); panel → `CivilianWork.assign`, movement →
`CivilianMovement`, estates → `ImprovementOrders`.

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Select | click medallion | tap medallion |
| March | click glowing neighbour tile | tap glowing neighbour tile |
| Work order | dossier button | dossier button |
| Empire roster | CIVILIANS chip / `C` | CIVILIANS chip |
| Visit crew | roster row / Visit | tap row / Visit |
| Estates ledger | `ESTATES` / province **Build Improvement** | same |
| Cancel / close | dossier / ledger Close | dossier / ledger Close |

## Tests

`test_civilian_catalog`, `test_civilian_movement`, `test_civilian_work`,
`test_civilian_roster`, `test_improvement_system`,
`test_map_screen_crown_orders`, `test_map_model`.

```bash
gd-tools test --coverage --min 80
```
