# Fleets and naval combat

Naval rules slice: sea-going fleets, one move per turn, docking at owned
harbours, the fog they reveal, and sea-zone battles.

**Pillars:** P2 (movement, ship reveal, combat), P3 (rules/view split), P1 (map
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
- `VisibilityModel.end_of_turn` handles fog decay, distant re-fog and the
  coastal pass; enemy markers show only on fully visible tiles.
- Hulls are stable instances (`ship_<n>`) with a catalog type; `ShipStats` holds
  the canonical FRP/RNG/ARM/HULL/MV, intercept, flee and cargo values.
- Fleets of two or more factions ending the turn in one sea zone fight. Side
  strength sums `FRP + 0.4·RNG + 0.15·ARM + 0.1·MV` per hull; durability sums
  `HULL × (1 + ARM/10)`.
- A 3% strength edge wins: the beaten squadron loses every hull, the victor
  absorbs half the beaten strength on its weakest hulls and keeps one.
  Near-equal strength stalemates; fleets in port never fight.

## Deferred (explicit, REQ-P2-02)

- Home-fleet merge at the capital; the capital port behaves like any harbour.
- Missions other than Move: Patrol, Blockade, Beachhead, Defend.
- Interception, retreat and trade raids.
- AI movement; enemy fleets hold station.
- Several hull counts per marker (a marker is a squadron).

## Architecture

| File | Role |
|------|------|
| `scripts/rules/fleet_state.gd` | owner, location, zone/province, moved flag, typed hulls |
| `scripts/rules/ship_stats.gd` | canonical per-type combat and cargo stats |
| `scripts/rules/naval_combat.gd` | contested zones, strength, battles, casualties |
| `scripts/rules/naval_movement.gd` | adjacency, destinations, validation, `apply_move` |
| `scripts/rules/visibility.gd` | per-player fog state (reveal plus end of turn) |
| `scripts/map/ship_layer.gd` | maps fleets to markers, applies orders, animates |
| `scripts/map/map_overlay.gd` | destination highlights over the fog layer |
| `scripts/ui/fleet_panel.gd` | station, squadron roster and remaining move |
| `scripts/map_screen.gd` | tap intents and end-of-turn wiring |

Rules code has no node dependencies (`REQ-P3-03`). Orders go through
`ShipLayer.order` then `NavalMovement.apply_move`; `MapScreen._resolve_naval_combat`
runs `NavalCombat.resolve_turn` at end of turn and prunes markers.

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Select fleet | click | tap |
| Sail / dock | click a highlight | tap a highlight |
| Cancel | `Esc` | close the panel |

Highlights appear for a selected player fleet with a move left; a refused order
raises the rule reason as a toast.

## Tests

`tests/test_naval_movement.gd` covers adjacency, the one-move limit, begin-turn
reset, ownership/harbour checks and destinations. `tests/test_fleet_orders.gd`
covers selection, move plus reveal, refusal, docking and marker visibility. Fog
lives in `tests/test_visibility.gd`; catalog and battles in
`tests/test_ship_stats.gd` and `tests/test_naval_combat.gd`.

```bash
gd-tools test --coverage --min 80
```
