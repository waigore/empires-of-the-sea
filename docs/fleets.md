# Fleets and naval combat

Movement, cargo, fog, sea battles; stations and raids:
[naval-missions.md](naval-missions.md).

**Pillars:** P2, P3, P1 (map feedback), P4 (no per-frame sim).

**Wiki:** [ships-and-naval](https://github.com/waigore/empires-of-the-sea/wiki/ships-and-naval),
[map-topology](https://github.com/waigore/empires-of-the-sea/wiki/map-topology),
[fog-and-exploration](https://github.com/waigore/empires-of-the-sea/wiki/fog-and-exploration).

## Implemented

- Sea zone or port, never both; one roster per region.
- **One move / turn:** S↔S; undock; dock at an owned port; a warp zone crosses.
- A new zone reveals water + **coastal ring**; fog decays.
- Hulls are instances (`ship_<n>` + type); `ShipStats` FRP/RNG/ARM/HULL/MV;
  `ShipEconomy` builds with tech gates, **2 food upkeep**.
- **Yard:** launch at the capital for its row + **one peasant**; breaking up
  returns one peasant, no refund; an emptied squadron retires (DR-20261109-01).
- **Home cargo:** merchant hulls in the home fleet give **cargo holds**
  (1/turn) capping **imports**; exports free (DR-20261109-03).
- **Home sortie** (DR-20261109-17): the home squadron may put to sea, spending
  its move and holds. Colonists ride as passengers (one per hull) and land
  beside the zone; a sunk squadron drowns them.
- Contested zones fight at turn end, at war: `FRP + 0.4·RNG + 0.15·ARM +
  0.1·MV`; durability `HULL × (1 + ARM/10)`; a 3% edge wins. A beaten side may
  retreat.
- **Multi-hull markers:** escorts, a hull badge and a gold strength gauge; the
  dossier prints the weighted maths, hull pool and zone share.
- **Stations:** Patrol, Blockade, Defend, Beachhead; one station or move per turn
  (DR-20261109-13, DR-20261109-16).
- **Army transport** (`NavalTransport`): an army boards in port (one regiment per
  hull), sails or crosses, and lands on an owned coast. Troops drown with a sunk
  squadron.
- **Beachhead:** a squadron marks a hostile coast beside its zone (spends the
  move); it opens next turn, the carried army lands and consumes it; unused
  markers lapse.

## Deferred (REQ-P2-02)

Home-fleet merge · raid hull losses (a raid takes cargo only, DR-20261110-13).

## Architecture

| File | Role |
|------|------|
| `scripts/rules/{fleet_state,fleet_missions,ship_stats,ship_economy}.gd` | location, stations, combat, build |
| `scripts/rules/{naval_strength,fleet_yard,trade_cargo,fleet_sortie}.gd` | strength maths, yard, cargo, sortie |
| `scripts/rules/{naval_combat,naval_movement,warp_travel,naval_interception,naval_retreat,naval_raid}.gd` | battles, moves, stations, raids |
| `scripts/rules/{naval_transport,civilian_voyage}.gd`, `scripts/map/{army_transport,map_play_beachhead,civilian_voyage_map}.gd` | board, land, beachhead, passengers |
| `scripts/ai/ai_naval_planner.gd`, `scripts/map/{map_play_fleet_ai,map_play_fleet_missions,map_play_raids}.gd` | rival sorties, stations, raids |
| `scripts/map/{ship_layer,ship_markers,fleet_rosters,map_overlay,map_play_warp,fog_layer}.gd` | orders, markers, rosters, highlights, fog |
| `scripts/ui/{fleet_panel,fleet_strength_section,fleet_crew_section,fleet_mission_section,panel_dock}.gd` | dossier, strength maths, passengers, stations, dock |
| `scripts/economy/economy_controller.gd`, `scripts/map_screen.gd` | upkeep, intents |

No node deps (`REQ-P3-03`).

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Select fleet | click | tap |
| Sail / dock | click highlight | tap highlight |
| Cross passage | click Passage ring | tap Passage ring |
| Take a station | dossier button | same |
| Land troops | dossier button | same |
| Take / land colonists | dossier **PASSENGERS** | same |
| Mark beachhead | dossier coast button | same |
| Shipyard | capital dossier → Shipyard | same |
| Cancel | `Esc` | close panel |

## Tests

`test_warp_travel`, `test_naval_movement`, `test_fleet_orders`,
`test_fleet_missions`, `test_fleet_rosters`, `test_visibility`,
`test_ship_stats`, `test_ship_economy`, `test_naval_combat`,
`test_naval_strength`, `test_naval_interception`, `test_naval_retreat`,
`test_naval_raid`, `test_fleet_yard`, `test_trade_cargo`, `test_civilian_voyage`,
`test_fleet_sortie`, `test_ai_rules`, `test_map_screen`.

```bash
gd-tools test --coverage --min 80
```
