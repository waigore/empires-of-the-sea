# Civilian units

Land units that explore, survey and improve the map. This milestone ships the
three starting civilians; the tech/diplomacy-gated three are catalogued but not
playable yet.

**Pillars:** P2, P3 (rules/view), P1 (map feedback), P4 (turn-based, no per-frame sim).

**Wiki:** [civilian-units](https://github.com/waigore/empires-of-the-sea/wiki/civilian-units),
[extraction-and-improvements](https://github.com/waigore/empires-of-the-sea/wiki/extraction-and-improvements),
[fog-and-exploration](https://github.com/waigore/empires-of-the-sea/wiki/fog-and-exploration).

## Implemented

- **Roster** (`CivilianCatalog`): all six wiki types with training costs
  (1,000 cash + 2 paper; 2,000 + 4 for Spy/Merchant/Rail Builder).
- **Playable:** Explorer (explore, prospect), Builder (build improvement),
  Engineer (build road, build port). Three mustered at the capital.
- **Training** in the capital province spends treasury + paper; only the
  starting three are available.
- **Movement:** one orthogonal land tile per turn. Explorers cross any land;
  Builders/Engineers stay inside their crown's provinces.
- **Work orders** target the unit's own tile, cost materials at assignment
  (not refunded on cancel) and resolve during the Build/Work pass at end of
  turn: explore `ceil(3 × province tiles / largest province)` (≤3 turns),
  prospect 1 turn (iron/coal/gold, per player), improvement level 1–4
  (1/1, 4/4, 8/8, 16/16 lumber+cast iron, level turns), road 1/1 (transport 1),
  port 5 lumber + 5 cast iron (2 turns, one per province).
- **Presence:** a civilian keeps its province fully visible for its owner, so
  charted land does not re-fog under an Explorer.
- **One crew per tile:** a second Builder/Engineer work order on the same tile
  for the same crown is refused.
- Panel shows posting, tile works, stores, each order's cost and every refusal
  reason in text (no hover-only UX).

## Deferred (REQ-P2-02)

- **Spy** — needs court reports, counter-spy and rival research intel.
- **Merchant** — `purchase_land` needs Minor Nations, embassies, at-war checks.
- **Rail Builder** — needs the transport tech tree and steel production.
- `upgrade_town`, `build_fort` — no town tiles or siege model yet.
- Road level 2 (`Road Construction`), relocation with the work order
  (`originTileKey`/`assignedTileKey`) and rival-owned civilian AI.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/civilian_catalog.gd` | roster, training costs, deferred flags |
| `scripts/rules/civilian_state.gd` | one unit: tile, move flag, work order |
| `scripts/rules/civilian_movement.gd` | adjacency, travel gates, presence |
| `scripts/rules/civilian_work.gd` | validation, costs, duration, completion |
| `scripts/rules/land_works.gd` | per-tile improvements, roads, ports, prospection |
| `scripts/rules/visibility.gd` | `reveal_province`, explorer-held provinces |
| `scripts/map/civilian_layer.gd` | markers, orders, development drawing |
| `scripts/map/civilian_marker.gd` | medallion glyphs and progress ring |
| `scripts/ui/civilian_panel.gd` | dossier, costs, refusal reasons |
| `scripts/map_screen.gd` | intents, training, end-of-turn wiring |

No node deps in rules (`REQ-P3-03`). Orders: panel → `CivilianWork.assign`;
movement: `CivilianLayer` → `CivilianMovement.apply_move`.

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Select | click medallion | tap medallion |
| March | click glowing neighbour tile | tap glowing neighbour tile |
| Work order | dossier button | dossier button |
| Cancel / close | dossier | dossier |

## Tests

`test_civilian_catalog`, `test_civilian_movement`, `test_civilian_work`,
`test_map_screen` (muster, dossier, work completion, training).

```bash
gd-tools test --coverage --min 80
```
