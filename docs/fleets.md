# Fleets and naval combat

Movement, harbours, cargo, fog, the yard and sea battles. Station orders,
interception, retreat and raids live in [naval-missions.md](naval-missions.md).

**Pillars:** P2, P3, P1 (map feedback), P4 (no per-frame sim).

**Wiki:** [ships-and-naval](https://github.com/waigore/empires-of-the-sea/wiki/ships-and-naval),
[map-topology](https://github.com/waigore/empires-of-the-sea/wiki/map-topology),
[fog-and-exploration](https://github.com/waigore/empires-of-the-sea/wiki/fog-and-exploration).

## Implemented

- At sea (zone) or in port (province), never both; one regional roster.
- **One move / turn:** S↔S; undock to adjacent sea; dock at an owned port; a
  warp zone crosses to its pair and the view follows.
- A new zone reveals water + **coastal ring**; fog decays.
- Hulls are instances (`ship_<n>` + type); `ShipStats` FRP/RNG/ARM/HULL/MV;
  `ShipEconomy` builds with tech gates, **2 food/hull upkeep**.
- **Yard:** launch a hull at the capital for its row + **one peasant** into the
  home fleet (or found it); break up a hull for one peasant back, no refund; an
  emptied squadron retires (DR-20261109-01).
- **Home cargo:** merchant hulls in the home fleet give **cargo holds**
  (1/turn) capping world-market **imports**; exports free (DR-20261109-03).
- Contested zones fight at turn end, only at war: `FRP + 0.4·RNG + 0.15·ARM +
  0.1·MV`; durability `HULL × (1 + ARM/10)`; a 3% edge wins (loser sunk,
  victor spends half), near-equal stalemates. A beaten side may retreat.
- **Stations:** Patrol, Blockade, Defend and Beachhead; one station or move per
  turn (DR-20261109-13, DR-20261109-16).
- **Army transport** (`NavalTransport`): a field army boards in port (one
  regiment per hull), sails or crosses a passage, and lands on an owned coast.
  Troops drown with a sunk squadron.
- **Beachhead:** a squadron marks a hostile coast beside its zone (spends the
  move); the marker opens next turn, its carried army lands and consumes it, and
  an unused marker lapses that turn's end.

## Deferred (REQ-P2-02)

Home-fleet merge · multi-hull markers · ship strength · merchant-hull losses in
a raid.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/{fleet_state,ship_stats,ship_economy}.gd` | location, combat/cargo, build, upkeep |
| `scripts/rules/fleet_yard.gd`, `trade_cargo.gd` | launch / break up, home cargo |
| `scripts/rules/{naval_combat,naval_movement,warp_travel}.gd` | battles, moves, passages |
| `scripts/rules/naval_transport.gd`, `scripts/map/{army_transport,map_play_beachhead}.gd` | board, land, beachhead, passage, losses |
| `scripts/ai/ai_naval_planner.gd`, `scripts/map/map_play_fleet_ai.gd` | rival sortie, stations |
| `scripts/rules/visibility.gd` | fog reveal + turn end |
| `scripts/map/{ship_layer,ship_markers,fleet_rosters}.gd` | orders/battles, markers, rosters |
| `scripts/map/{map_overlay,map_play_warp,fog_layer}.gd` | highlights, warp, fog |
| `scripts/ui/{fleet_panel,panel_dock}.gd` | dossier, dock |
| `scripts/economy/economy_controller.gd` | upkeep, cargo status |
| `scripts/map_screen.gd` | intents + turn wiring |

No node deps (`REQ-P3-03`). Orders → `NavalMovement`; yard → `FleetYard`;
combat → `NavalCombat`.

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Select fleet | click | tap |
| Sail / dock | click highlight | tap highlight |
| Cross passage | click Passage ring | tap Passage ring |
| Land troops | dossier button | same |
| Mark beachhead | dossier coast button | same |
| Shipyard | capital dossier → Shipyard | same |
| Cancel | `Esc` | close panel |

## Tests

`test_warp_travel`, `test_naval_movement`, `test_fleet_orders`,
`test_fleet_rosters`, `test_visibility`, `test_ship_stats`, `test_ship_economy`,
`test_naval_combat` (in `test_battle_rules`), `test_fleet_yard`,
`test_trade_cargo`, `test_ai_rules`, `test_map_screen`.

```bash
gd-tools test --coverage --min 80
```
