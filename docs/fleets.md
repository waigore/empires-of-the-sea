# Fleets and naval combat

Naval slice: movement, fog, battles, upkeep, yard.

**Pillars:** P2, P3 (rules/view), P1 (map feedback), P4 (no per-frame fleet sim).

**Wiki:** [ships-and-naval](https://github.com/waigore/empires-of-the-sea/wiki/ships-and-naval),
[map-topology](https://github.com/waigore/empires-of-the-sea/wiki/map-topology),
[fog-and-exploration](https://github.com/waigore/empires-of-the-sea/wiki/fog-and-exploration).

## Implemented

- At sea (one zone) or in port (one province), never both; only Great Powers
  keep fleets, one roster per region.
- **One move / turn:** S↔S; undock to an adjacent sea; dock at an owned coastal
  province with `port_tile`.
- **Passage crossing:** a warp-zone fleet may cross to the paired zone as its
  move; the view follows.
- Entering a zone reveals water + the **coastal ring**; fog decays at turn end.
- Hulls are instances (`ship_<n>` + type); `ShipStats` holds FRP/RNG/ARM/HULL/MV,
  intercept, flee, cargo; `ShipEconomy` build rows, tech gates, **2 food/hull upkeep**.
- **Naval yard** (capital port): launch any tech-unlocked hull for its row plus
  **one peasant**; it joins or founds the home fleet. Dossier shows Σ FRP.
- **Breaker's yard:** break up one hull (port or sea); one peasant returns, no
  refund, an emptied squadron retires. It asks once: arm, then scrap
  (DR-20261109-01).
- **Home cargo:** merchant hulls in the home fleet (in port at the crown's seat)
  give **cargo holds** — 1 unit each per turn — capping world-market **imports**.
  The opening muster moors a Fluyte there (4 holds); exports need none. The
  ledger shows holds/free and locks Buy when full (DR-20261109-03).
- Contested zones fight at turn end **in every region**; only factions **at war**
  engage. Strength `FRP + 0.4·RNG + 0.15·ARM + 0.1·MV`; durability
  `HULL × (1 + ARM/10)`; a 3% edge wins (loser sunk, victor spends half the
  beaten strength on weakest hulls); near-equal stalemates; port fleets never
  fight.

## Deferred (REQ-P2-02)

Home-fleet merge over docking · overseas extraction cargo reservation ·
Patrol/Blockade/Beachhead/Defend · interception/retreat/raids · AI movement ·
multi-hull markers · docket ship strength beside land strength.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/{fleet_state,ship_stats,ship_economy}.gd` | location, combat/cargo stats, build rows, upkeep |
| `scripts/rules/fleet_yard.gd`, `trade_cargo.gd` | launch / break up, home-fleet cargo gate |
| `scripts/rules/{naval_combat,naval_movement,warp_travel}.gd` | battles, movement, passages |
| `scripts/rules/visibility.gd` | fog reveal + end of turn |
| `scripts/map/ship_layer.gd` | markers, orders, battles |
| `scripts/map/map_overlay.gd` | destination highlights |
| `scripts/map/fog_layer.gd` | fog texture + fade |
| `scripts/map/map_play_warp.gd` | crossing view |
| `scripts/ui/fleet_panel.gd` | dossier, yard orders |
| `scripts/ui/panel_dock.gd` | left/right dock side + `user://ui.cfg` |
| `scripts/economy/economy_controller.gd` | upkeep, cargo status |
| `scripts/map_screen.gd` | intents + end-of-turn wiring |

No node deps in rules (`REQ-P3-03`). `ShipLayer.order` →
`NavalMovement.apply_move`; yard: `ShipLayer.launch_hull` → `FleetYard`; combat:
`ShipLayer.resolve_battles` → `NavalCombat.resolve_turn`.

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Select fleet | click | tap |
| Sail / dock | click highlight | tap highlight |
| Cross passage | click ring | tap ring |
| Shipyard | capital dossier → Shipyard | same |
| Cancel | `Esc` | close panel |

## Tests

`test_warp_travel`, `test_naval_movement`, `test_fleet_orders`, `test_visibility`,
`test_ship_stats`, `test_ship_economy`, `test_naval_combat`, `test_fleet_yard`,
`test_trade_cargo`, `test_map_screen`.

```bash
gd-tools test --coverage --min 80
```
