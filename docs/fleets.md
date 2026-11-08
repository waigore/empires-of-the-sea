# Fleet movement

First rules slice for the naval domain: sea-going fleets, one move per turn,
docking at owned harbours, and the fog their moves reveal.

**Pillars:** P2 (movement, ship reveal), P3 (rules/view split), P1 (map
feedback), P4 (no per-frame fleet simulation).

**Wiki:** [ships-and-naval](https://github.com/waigore/empires-of-the-sea/wiki/ships-and-naval),
[map-topology](https://github.com/waigore/empires-of-the-sea/wiki/map-topology),
[fog-and-exploration](https://github.com/waigore/empires-of-the-sea/wiki/fog-and-exploration).

## Implemented rules

- A fleet is **at sea** in one sea zone or **in port** at one province; the two
  are exclusive.
- **One move per turn**: sea → adjacent sea zone; port → adjacent sea zone
  (undock); sea → owned coastal province adjacent to the fleet's zone (dock).
- Docking requires ownership and a **harbour tile** (`port_tile`).
- Entering a zone reveals its water and strict **coastal land ring** through
  `VisibilityModel.reveal_sea_zone`.
- `VisibilityModel.end_of_turn` handles fog decay, distant-zone re-fog and the
  coastal pass; zones with a friendly fleet at sea are occupied. Enemy markers
  are drawn only on fully visible tiles.

## Deferred (explicit, REQ-P2-02)

- Home-fleet merge at the capital; the capital port behaves like any harbour.
- Missions other than Move: Patrol, Blockade, Beachhead, Defend.
- Interception and naval combat; two fleets may share a zone.
- AI movement; enemy fleets hold station.
- Multiple hull instances per fleet marker.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/fleet_state.gd` | owner, location, zone/province, moved flag |
| `scripts/rules/naval_movement.gd` | adjacency, destinations, validation, `apply_move` |
| `scripts/rules/visibility.gd` | per-player fog state (reveal plus end of turn) |
| `scripts/map/ship_layer.gd` | maps fleets to markers, applies orders, animates |
| `scripts/map/map_overlay.gd` | destination highlights over the fog layer |
| `scripts/ui/fleet_panel.gd` | station and remaining move |
| `scripts/map_screen.gd` | tap intents and end-of-turn wiring |

Rules code has no node dependencies (`REQ-P3-03`). `MapScreen._try_fleet_order`
is the only input entry point; it delegates to `ShipLayer.order` and then
`NavalMovement.apply_move`.

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Select fleet | click | tap |
| Sail / dock | click a highlight | tap a highlight |
| Cancel | `Esc` | close the panel |

Highlights appear only for a selected player fleet with a move left. An
unreachable zone raises the rule reason as a toast.

## Tests

`tests/test_naval_movement.gd` covers adjacency, the one-move limit, begin-turn
reset, ownership/adjacency/harbour checks, undock and destination lists.
`tests/test_fleet_orders.gd` covers selection, move plus reveal, second-move
refusal, docking, enemy refusal, end-turn reset and marker visibility. Fog rules
live in `tests/test_visibility.gd`.

```bash
gd-tools test --coverage --min 80
```
