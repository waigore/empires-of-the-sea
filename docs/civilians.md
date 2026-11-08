# Civilian units

Land units that explore, survey and improve the map. This milestone ships the
three starting civilians; the tech/diplomacy-gated three are catalogued but not
playable yet.

**Pillars:** P2, P3 (rules/view), P1 (map feedback), P4 (turn-based).

**Wiki:** [civilian-units](https://github.com/waigore/empires-of-the-sea/wiki/civilian-units),
[extraction-and-improvements](https://github.com/waigore/empires-of-the-sea/wiki/extraction-and-improvements),
[fog-and-exploration](https://github.com/waigore/empires-of-the-sea/wiki/fog-and-exploration).

## Implemented

- **Roster** (`CivilianCatalog`): all six wiki types with training costs.
- **Playable:** Explorer (explore, prospect), Builder (build improvement),
  Engineer (road, port). Three muster at the capital.
- **Training** at the capital spends treasury + paper; starting three only.
- **Movement:** one orthogonal land tile per turn; Builders/Engineers stay in
  their crown's provinces.
- **Work orders** target the unit's tile or, for a Builder, any owned resource
  tile: the unit records `origin_tile` / `assigned_tile`, relocates and returns
  on cancel. Costs are paid at assignment and not refunded. Explore ≤3 turns,
  prospect 1, improvement 1–4 at level turns (1/4/8/16 lumber + cast iron),
  road 1, port 5 + 5 (2 turns). Mines need prospecting first.
- **Improvements** are named from the resource (Farm, Lumber camp, Mine,
  Pasture, Ranch) and yield `min(level, tech cap, transport, town)` at end of
  turn when connected by road/port/town. Mines need prospecting first; upgrades
  above the tech cap (1 without a gathering tech tree) are refused.
- **Estates ledger** (`ESTATES`): realm-wide yield, blockers, filters and
  Build / Cancel / Map. See [`improvements.md`](improvements.md).
- **Presence** keeps a province visible; one crew per tile per crown.
- Panel states costs and every refusal reason in text.

## Deferred (REQ-P2-02)

- **Spy** — court reports, counter-spy, rival research intel.
- **Merchant** — `purchase_land` needs Minor Nations and embassies.
- **Rail Builder** — transport tech tree and steel production.
- `upgrade_town`, `build_fort`, road level 2, rival civilian AI.
- Improvement transport caps, raw → manufactured production, riches conversion.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/civilian_*.gd` | roster, state, movement, work validation |
| `scripts/rules/land_works.gd`, `improvement_*.gd` | tile works, connectivity, extraction, ledger |
| `scripts/map/civilian_layer.gd` | markers, orders, development drawing |
| `scripts/ui/civilian_panel.gd`, `improvement_panel.gd` | dossier and estates ledger |
| `scripts/map_screen.gd` | intents, training, end-of-turn wiring |

No node deps in rules (`REQ-P3-03`). Panel → `CivilianWork.assign`; movement →
`CivilianMovement.apply_move`; estates → `ImprovementOrders`.

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
