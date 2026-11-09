# Fleets and naval combat

Naval slice: movement, harbours, fog, battles and the yard.

**Pillars:** P2, P3, P1 (map feedback), P4 (no per-frame sim).

**Wiki:** [ships-and-naval](https://github.com/waigore/empires-of-the-sea/wiki/ships-and-naval),
[map-topology](https://github.com/waigore/empires-of-the-sea/wiki/map-topology),
[fog-and-exploration](https://github.com/waigore/empires-of-the-sea/wiki/fog-and-exploration).

## Implemented

- At sea (one zone) or in port (one province), never both. Only Great Powers
  keep fleets; each region hosts its squadrons.
- **One move / turn:** S↔S; undock to an adjacent sea; dock at an owned port
  province with `port_tile`.
- **Passage crossing:** a fleet in a warp zone may cross to the paired zone;
  the view follows.
- Entering a zone reveals water + the **coastal land ring**; fog decays later.
- Hulls are instances (`ship_<n>` + type); `ShipStats` holds FRP/RNG/ARM/HULL/MV,
  cargo; `ShipEconomy` the rows, gates and **2 food/hull upkeep**.
- **Naval yard** (capital port): launch a tech-unlocked hull for its row plus
  **one peasant**; it joins — or founds — the home fleet (Σ FRP).
- **Breaker's yard:** break up one hull (port or sea); one peasant returns, no
  refund, an emptied squadron retires; arm, then scrap (DR-20261109-01).
- Contested zones fight at turn end **in every region**, only between factions
  **at war**. Strength `FRP + 0.4·RNG + 0.15·ARM + 0.1·MV`; durability
  `HULL × (1 + ARM/10)`; a 3% edge wins (loser sunk, victor spends half the
  beaten strength on weakest hulls); near-equal is a stalemate; port fleets
  never fight.
- **Rival squadrons sail** (`AiNavalPlanner`): at war a rival sorties from port
  or pursues one zone onto a squadron it can match; at peace it holds
  station. A move into a charted zone earns one sighting line.

## Deferred (REQ-P2-02)

Home-fleet merge · player missions · interception/retreat/raids · rivals
sailing home · multi-hull markers · docket ship strength.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/fleet_state.gd` | location, move flag, hulls |
| `scripts/rules/ship_stats.gd` | combat catalog |
| `scripts/rules/ship_economy.gd` | build costs, gates, era, upkeep |
| `scripts/rules/fleet_yard.gd` | launch / break up hulls |
| `scripts/rules/naval_combat.gd` | contested zones, casualties |
| `scripts/rules/naval_movement.gd` | adjacency, `apply_move` |
| `scripts/rules/warp_travel.gd` | crossing validation |
| `scripts/map/map_play_warp.gd` | follows a crossing |
| `scripts/ai/ai_naval_planner.gd` | rival sortie, pursue, hold |
| `scripts/map/map_play_fleet_ai.gd` | rival sea pass, sightings |
| `scripts/rules/visibility.gd` | fog reveal, turn end |
| `scripts/map/ship_layer.gd` | markers, orders |
| `scripts/map/map_overlay.gd` | highlights |
| `scripts/ui/fleet_panel.gd` | dossier, yard orders |
| `scripts/ui/panel_dock.gd` | dock side, `user://ui.cfg` |
| `scripts/economy/economy_controller.gd` | upkeep |
| `scripts/map_screen.gd` | intents + turn wiring |

No node deps in rules (`REQ-P3-03`). Orders `ShipLayer.order` →
`NavalMovement.apply_move`; yard `launch_hull` → `FleetYard`; combat
`resolve_battles` → `NavalCombat.resolve_turn`.

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Select fleet | click | tap |
| Sail / dock | click highlight | tap highlight |
| Cross passage | click Passage ring | tap Passage ring |
| Shipyard | capital dossier → Shipyard | same |
| Cancel | `Esc` | close panel |

## Tests

`test_naval_movement`, `test_fleet_orders`, `test_visibility`, `test_ai_rules`
(rival sail), `test_map_screen` and the ship/combat unit suites.

```bash
gd-tools test --coverage --min 80
```
