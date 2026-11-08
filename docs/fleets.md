# Fleets and naval combat

Naval slice: fleets, one move per turn, owned harbours, fog reveal, sea battles,
food upkeep, and ship catalogs.

**Pillars:** P2, P3 (rules/view), P1 (map feedback), P4 (no per-frame fleet sim).

**Wiki:** [ships-and-naval](https://github.com/waigore/empires-of-the-sea/wiki/ships-and-naval),
[map-topology](https://github.com/waigore/empires-of-the-sea/wiki/map-topology),
[fog-and-exploration](https://github.com/waigore/empires-of-the-sea/wiki/fog-and-exploration).

## Implemented

- Fleet is **at sea** (one zone) or **in port** (one province) — exclusive.
- Only Great Powers keep fleets; each region hosts its own squadrons, and the
  map screen swaps them with the Old/New World view.
- **One move / turn:** S↔S; port → adjacent sea (undock); sea → owned coastal
  province adjacent to the zone (dock). Dock needs ownership + `port_tile`.
- Entering a zone reveals water + **coastal land ring** via
  `VisibilityModel.reveal_sea_zone`. End-of-turn fog decay / distant re-fog /
  coastal pass; enemy markers only on fully visible tiles.
- Hulls are instances (`ship_<n>` + type). `ShipStats`: FRP/RNG/ARM/HULL/MV,
  intercept, flee, cargo. `ShipEconomy`: build treasury/materials, unlock eras,
  **2 food/hull upkeep** (shown on the fleet dossier).
- **Upkeep is empire-wide:** every region's squadrons eat, and the HUD SHIPS
  chip is a total, so viewing the New World cannot hide the Old World fleet's
  cost.
- Contested sea zones fight at end of turn **in every region**, including the
  one off screen; an off-screen result is prefixed with its region in the toast.
  Only fleets of factions **at war** engage; at peace they share a zone, and a
  neutral third party stays out of someone else's battle. Strength
  `FRP + 0.4·RNG + 0.15·ARM + 0.1·MV`; durability
  `HULL × (1 + ARM/10)`. 3% edge wins (loser sunk; victor takes half strength on
  weakest hulls, keeps one). Stalemate if near-equal; port fleets never fight.

## Deferred (REQ-P2-02)

Home-fleet merge · Patrol/Blockade/Beachhead/Defend · interception/retreat/raids
· build deduct + tech unlock · AI movement · multi-hull markers · sail through
warp zones (Old ↔ New World).

## Architecture

| File | Role |
|------|------|
| `scripts/rules/fleet_state.gd` | location, move flag, typed hulls |
| `scripts/rules/ship_stats.gd` | combat / cargo catalog |
| `scripts/rules/ship_economy.gd` | build costs, era, food upkeep |
| `scripts/rules/naval_combat.gd` | contested zones, casualties |
| `scripts/rules/naval_movement.gd` | adjacency, validate, `apply_move` |
| `scripts/rules/visibility.gd` | fog reveal + end of turn |
| `scripts/map/ship_layer.gd` | markers, orders, all-region battles |
| `scripts/map/map_overlay.gd` | destination highlights |
| `scripts/ui/fleet_panel.gd` | dockable station/roster dossier |
| `scripts/ui/panel_dock.gd` | left/right dock side + `user://ui.cfg` |
| `scripts/economy/economy_controller.gd` | all-region upkeep into Consumption |
| `scripts/map_screen.gd` | intents + end-of-turn wiring |

No node deps in rules (`REQ-P3-03`). Orders: `ShipLayer.order` →
`NavalMovement.apply_move`. Combat: `ShipLayer.resolve_battles` →
`NavalCombat.resolve_turn`.

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Select fleet | click | tap |
| Sail / dock | click highlight | tap highlight |
| Cancel | `Esc` | close panel |

Highlights for a selected player fleet with a move left; refused orders toast.

## Tests

`test_naval_movement`, `test_fleet_orders`, `test_visibility`, `test_ship_stats`,
`test_ship_economy`, `test_naval_combat`, `test_map_screen`.

```bash
gd-tools test --coverage --min 80
```
