# Civilian units

Land units that explore, survey and improve the map. The starting three and the
tech-gated Rail Builder ship; Spy and Merchant are catalogued but blocked.

**Pillars:** P2, P3 (rules/view), P1 (map feedback), P4 (turn-based).

**Wiki:** [civilian-units](https://github.com/waigore/empires-of-the-sea/wiki/civilian-units),
[extraction-and-improvements](https://github.com/waigore/empires-of-the-sea/wiki/extraction-and-improvements),
[fog-and-exploration](https://github.com/waigore/empires-of-the-sea/wiki/fog-and-exploration).

## Implemented

- **Roster** (`CivilianCatalog`): all six wiki types with training costs.
- **Playable:** Explorer (explore, prospect), Builder (build improvement),
  Engineer (road, improved road, port), Rail Builder (railroad). The starting
  three muster at the capital.
- **Training** at the capital spends treasury + paper; the Rail Builder waits
  for Early Steam Engine.
- **Movement:** one orthogonal land tile per turn; Builders, Engineers and Rail
  Builders stay in their crown's provinces.
- **Work orders** target the unit's tile or, for a Builder, any owned resource
  tile: the unit records `origin_tile` / `assigned_tile`, relocates and returns
  on cancel. Costs are paid at assignment and not refunded. Explore ≤3 turns,
  prospect 1, improvement 1–4 at level turns (1/4/8/16 lumber + cast iron),
  road 1 + 1 (level 2 needs Road Construction), port 5 + 5 (2 turns), rail
  2 lumber + 2 steel (2 turns, road 1–2 → 4), fort 1–3 ([forts.md](forts.md)).
  Mines need prospecting first.
- **Improvements** are named from the resource (Farm, Lumber camp, Mine,
  Pasture, Ranch) and yield `min(level, tech cap, transport, town)` at end of
  turn when connected by road/port/town. Mines need prospecting first; upgrades
  above the tech cap (1 without a gathering tech tree) are refused.
- **Estates ledger** (`ESTATES`): realm-wide yield, blockers, filters and
  Build / Cancel / Map. See [`improvements.md`](improvements.md).
- **Presence** keeps a province visible; one crew per tile per crown (Rail
  Builders exempt).
- Panel states costs and every refusal reason in text.

## Deferred (REQ-P2-02)

- **Spy** — counter-spy and court reports need rival spies, rival research and
  AI activity to observe; presence reveal already ships with every civilian.
- **Merchant** — `purchase_land` needs tile-level land ownership and overseas
  cargo connectivity; embassies and Merchant Companies already exist.
- `upgrade_town` (town connectivity), rival civilian AI.
- Improvement transport caps, raw → manufactured production, riches conversion.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/civilian_*.gd` | roster, state, movement, work validation |
| `scripts/rules/civilian_transport.gd` | roads, improved road, port, rail |
| `scripts/rules/land_works.gd`, `improvement_*.gd` | tile works, connectivity, extraction, ledger |
| `scripts/map/civilian_layer.gd` | markers, orders, development drawing |
| `scripts/ui/civilian_panel.gd`, `improvement_panel.gd` | dossier and estates ledger |
| `scripts/map_screen.gd` | intents, training, end-of-turn wiring |

No node deps in rules (`REQ-P3-03`). Panel → `CivilianWork.assign`; movement →
`CivilianMovement.apply_move`; transport → `CivilianTransport`; estates →
`ImprovementOrders`.

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
`test_improvement_system`, `test_map_screen`.

```bash
gd-tools test --coverage --min 80
```
