# Fleets and naval combat

Naval slice: movement, harbours, fog, battles, upkeep and the naval yard.

**Pillars:** P2, P3, P1 (map feedback), P4 (no per-frame sim).

**Wiki:** [ships-and-naval](https://github.com/waigore/empires-of-the-sea/wiki/ships-and-naval),
[map-topology](https://github.com/waigore/empires-of-the-sea/wiki/map-topology),
[fog-and-exploration](https://github.com/waigore/empires-of-the-sea/wiki/fog-and-exploration).

## Implemented

- At sea (one zone) or in port (one province), never both; only Great Powers
  keep fleets, one roster per region.
- **One move / turn:** S↔S; undock to adjacent sea; dock at owned coastal
  province with `port_tile`.
- **Passage crossing:** warp-zone fleet crosses to paired zone; view follows.
- Entering a zone reveals water + **coastal ring**; fog decays at turn end.
- Hulls are instances (`ship_<n>` + type); `ShipStats` FRP/RNG/ARM/HULL/MV,
  intercept, flee, cargo; `ShipEconomy` build rows, tech gates, **2 food/hull
  upkeep**.
- **Naval yard** (capital port): launch tech-unlocked hull for row + **one
  peasant**; joins or founds home fleet (Σ FRP).
- **Breaker's yard:** scrap one hull (port or sea); peasant returns, no refund;
  emptied squadron retires; arm, then scrap (DR-20261109-01).
- **Home cargo:** merchant hulls in home fleet (port at crown seat) give
  **cargo holds** (1/turn) capping world-market **imports**. Opening muster
  moors a Fluyte (4 holds); exports need no hold. Ledger shows holds / free
  space and locks Buy when full (DR-20261109-03).
- Contested zones fight at turn end **in every region**, only factions **at
  war**. Strength `FRP + 0.4·RNG + 0.15·ARM + 0.1·MV`; durability
  `HULL × (1 + ARM/10)`; 3% edge wins (loser sunk, victor spends half beaten
  strength on weakest hulls); near-equal stalemates; port fleets never fight.
- **Rival squadrons sail** (`AiNavalPlanner`): at war a rival sorties from port
  or pursues one zone onto a squadron it can match; at peace holds station.
  Charted-zone moves earn one sighting line.

## Deferred (REQ-P2-02)

Home-fleet merge · overseas extraction cargo · Patrol/Blockade/Beachhead/Defend ·
interception/retreat/raids · rivals sailing home · multi-hull markers · docket
ship strength beside land strength.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/{fleet_state,ship_stats,ship_economy}.gd` | location, combat/cargo, build, upkeep |
| `scripts/rules/fleet_yard.gd`, `trade_cargo.gd` | launch / break up, home cargo |
| `scripts/rules/{naval_combat,naval_movement,warp_travel}.gd` | battles, moves, passages |
| `scripts/ai/ai_naval_planner.gd` | rival sortie, pursue, hold |
| `scripts/map/map_play_fleet_ai.gd` | rival sea pass, sightings |
| `scripts/rules/visibility.gd` | fog reveal + turn end |
| `scripts/map/ship_layer.gd` | markers, orders, battles |
| `scripts/map/{map_overlay,map_play_warp,fog_layer}.gd` | highlights, warp, fog |
| `scripts/ui/fleet_panel.gd`, `panel_dock.gd` | dossier + yard, dock |
| `scripts/economy/economy_controller.gd` | upkeep, cargo status |
| `scripts/map_screen.gd` | intents + turn wiring |

No node deps in rules (`REQ-P3-03`). Orders → `NavalMovement`; yard →
`FleetYard`; combat → `NavalCombat`.

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Select fleet | click | tap |
| Sail / dock | click highlight | tap highlight |
| Cross passage | click Passage ring | tap Passage ring |
| Shipyard | capital dossier → Shipyard | same |
| Cancel | `Esc` | close panel |

## Tests

`test_warp_travel`, `test_naval_movement`, `test_fleet_orders`, `test_visibility`,
`test_ship_stats`, `test_ship_economy`, `test_naval_combat`, `test_fleet_yard`,
`test_trade_cargo`, `test_ai_rules` (rival sail), `test_map_screen`.

```bash
gd-tools test --coverage --min 80
```
