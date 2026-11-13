# Fleets and naval combat

Movement, cargo, fog, battles; stations, raids:
[naval-missions.md](naval-missions.md).

**Pillars:** P2, P3, P1, P4.

**Wiki:** [ships-and-naval](https://github.com/waigore/empires-of-the-sea/wiki/ships-and-naval),
[fog-and-exploration](https://github.com/waigore/empires-of-the-sea/wiki/fog-and-exploration).

## Implemented

- Sea zone or port, never both; one roster/region.
- **One move / turn:** S↔S; undock; dock at an owned port; a warp zone crosses.
- A new zone reveals water + **coastal ring**; fog decays.
- Hulls are instances (`ship_<n>` + type); `ShipStats` FRP/RNG/ARM/HULL/MV;
  `ShipEconomy` builds with tech gates, **2 food upkeep**.
- **Named hulls** (`ShipNames`): period names, unique per squadron, kept
  through save and merge (DR-20261111-07).
- **Yard:** launch for its row + **one peasant**; the hull lands next turn at
  Build/work; breaking up returns a peasant, no refund (DR-20261109-01).
- **Home cargo:** merchant hulls give **cargo holds** (1/turn) capping
  **imports**; exports free (DR-20261109-03).
- **Home-fleet merge:** docking at the seat or a dossier **Join the home
  fleet** tap folds it in (`FleetHomeMerge`); ids, names and passengers
  keep; old saves repair.
- **Home sortie** (DR-20261109-17): the home squadron may sail, spending move
  and holds; colonists ride as passengers (one per hull) and land beside the
  zone.
- Contested zones fight at turn end: `FRP + 0.4·RNG + 0.15·ARM + 0.1·MV`;
  durability `HULL × (1 + ARM/10)`; a 3% edge wins, the loser retreats.
- **Markers:** escorts, hull badge and her strength; a sighted rival prints
  `*`, her dossier `???`, until watched across a turn (DR-20261113-20).
- **Stations:** Patrol, Blockade, Defend, Beachhead; one station or move/turn
  (DR-20261109-13, DR-20261109-16).
- **Army transport** (`NavalTransport`): an army boards in port (one regiment per
  hull), sails or crosses and lands on an owned coast; troops drown with a sunk
  squadron.
- **Beachhead:** a squadron marks a hostile coast (spends the move); the army
  lands next turn; unused markers lapse.

Raids sink one merchant hull (DR-20261111-17).

## Architecture

| File | Role |
|------|------|
| `scripts/rules/{fleet_state,fleet_missions,ship_stats,ship_economy}.gd` | location, stations, combat, build |
| `scripts/rules/{naval_strength,fleet_yard,trade_cargo,fleet_sortie,fleet_home_merge}.gd` | strength, yard, cargo, sortie, home merge |
| `scripts/rules/{naval_*,warp_travel}.gd` | battles, moves, stations, raids |
| `scripts/rules/{naval_transport,civilian_voyage}.gd`, `scripts/map/{army_transport,map_play_beachhead,civilian_voyage_map}.gd` | board, land, beachhead |
| `scripts/ai/ai_naval_planner.gd`, `scripts/map/{map_play_fleet_ai,map_play_fleet_missions,map_play_raids}.gd` | rival sorties, stations, raids |
| `scripts/map/{map_play_fleets,map_play_fleet_yard}.gd` | sail orders, fog intel, shipyard |
| `scripts/map/{ship_layer,ship_markers,fleet_rosters,map_overlay,map_play_warp,fog_layer}.gd` | orders, markers, rosters, fog |
| `scripts/ui/{fleet_panel,fleet_*_section,panel_dock}.gd` | dossier, strength, passengers, stations |
| `scripts/economy/economy_controller.gd`, `scripts/map_screen.gd` | upkeep, intents |

No node deps (`REQ-P3-03`).

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Select fleet | click | tap |
| Sail / dock | click highlight | tap highlight |
| Join home fleet | dossier button | same |
| Passages | click ring | tap ring |
| Take a station | dossier button | same |
| Land troops | dossier button | same |
| Take / land colonists | dossier **PASSENGERS** | same |
| Mark beachhead | dossier coast button | same |
| Shipyard | capital dossier → Shipyard | same |
| Cancel | `Esc` | close panel |

## Tests

`test_naval_rules`, `test_fleet_orders`,
`test_ship_*`, `test_economy_rules`, `test_civilian_voyage`, `test_home_merge`,
`test_visibility`, `test_map_screen`.

```bash
gd-tools test --coverage --min 80
```
