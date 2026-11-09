# Fleets and naval combat

Naval slice: movement, harbours, fog, battles, upkeep and the naval yard.

**Pillars:** P2, P3, P1 (map feedback), P4 (no per-frame sim).

**Wiki:** [ships-and-naval](https://github.com/waigore/empires-of-the-sea/wiki/ships-and-naval),
[map-topology](https://github.com/waigore/empires-of-the-sea/wiki/map-topology),
[fog-and-exploration](https://github.com/waigore/empires-of-the-sea/wiki/fog-and-exploration).

## Implemented

- At sea (one zone) or in port (one province), never both; Great Powers keep
  fleets, one roster per region.
- **One move / turn:** S↔S; undock to adjacent sea; dock at owned coastal
  province with `port_tile`.
- **Passage crossing:** warp-zone fleet crosses to paired zone; view follows.
- Entering a zone reveals water + **coastal ring**; fog decays at turn end.
- Hulls are instances (`ship_<n>` + type); `ShipStats` FRP/RNG/ARM/HULL/MV;
  `ShipEconomy` build rows, tech gates, **2 food/hull upkeep**.
- **Naval yard** (capital port): launch a hull for its row + **one peasant**;
  joins or founds home fleet (Σ FRP).
- **Breaker's yard:** scrap one hull (port or sea); peasant returns, no refund;
  emptied squadron retires; arm, scrap (DR-20261109-01).
- **Home cargo:** merchant hulls in the home fleet (port at the crown seat)
  give **cargo holds** (1/turn) capping world-market **imports**. A Fluyte
  (4 holds) opens; exports free (DR-20261109-03).
- Contested zones fight at turn end, only at war. Strength
  `FRP + 0.4·RNG + 0.15·ARM + 0.1·MV`; durability `HULL × (1 + ARM/10)`; 3%
  edge wins (loser sunk, victor spends half on weakest hulls); near-equal
  stalemates.
- **Rival squadrons sail** (`AiNavalPlanner`): at war it sorties or pursues one
  zone onto a match; at peace it holds. Charted moves earn a sighting.
- **Army transport** (`NavalTransport`): a field army boards a squadron in port
  (one regiment per hull), sails or crosses a passage, and lands on an owned
  coast beside the zone. Troops drown with a sunk squadron; hostile shores
  need a beachhead.

## Deferred (REQ-P2-02)

Home-fleet merge · Patrol/Blockade/Beachhead/Defend · interception/retreat/raids
· multi-hull markers · docket ship strength.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/{fleet_state,ship_stats,ship_economy}.gd` | location, combat/cargo, build, upkeep |
| `scripts/rules/fleet_yard.gd`, `trade_cargo.gd` | launch / break up, home cargo |
| `scripts/rules/{naval_combat,naval_movement,warp_travel}.gd` | battles, moves, passages |
| `scripts/rules/naval_transport.gd`, `scripts/map/army_transport.gd` | board, land, passage, losses |
| `scripts/ai/ai_naval_planner.gd` | rival sortie, pursue, hold |
| `scripts/map/map_play_fleet_ai.gd` | rival sea pass, sightings |
| `scripts/rules/visibility.gd` | fog reveal + turn end |
| `scripts/map/{ship_layer,ship_markers,fleet_rosters}.gd` | orders/battles, markers, rosters |
| `scripts/map/{map_overlay,map_play_warp,fog_layer}.gd` | highlights, warp, fog |
| `scripts/ui/fleet_panel.gd`, `panel_dock.gd` | dossier, yard, dock |
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
| Shipyard | capital dossier → Shipyard | same |
| Cancel | `Esc` | close panel |

## Tests

`test_warp_travel`, `test_naval_movement`, `test_fleet_orders`,
`test_fleet_rosters`, `test_visibility`, `test_ship_stats`, `test_ship_economy`,
`test_naval_combat`, `test_fleet_yard`, `test_trade_cargo`,
`test_ai_rules`, `test_map_screen`.

```bash
gd-tools test --coverage --min 80
```
