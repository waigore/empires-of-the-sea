# Fleets and naval combat

Naval slice: movement, harbours, fog, battles, upkeep and the yard.

**Pillars:** P2, P3 (rules/view), P1 (map feedback), P4 (no per-frame fleet sim).

**Wiki:** [ships-and-naval](https://github.com/waigore/empires-of-the-sea/wiki/ships-and-naval),
[map-topology](https://github.com/waigore/empires-of-the-sea/wiki/map-topology),
[fog-and-exploration](https://github.com/waigore/empires-of-the-sea/wiki/fog-and-exploration).

## Implemented

- At sea (one zone) or in port (one province); Great Powers only, per region.
- **One move / turn:** S↔S; undock to an adjacent sea; dock at an owned coastal
  province.
- **Passage crossing:** a fleet in a warp zone may cross to the paired zone as
  its move.
- Entering a zone reveals water + the **coastal land ring**; fog decays at turn
  end.
- Hulls are instances (`ship_<n>` + type); `ShipStats` holds combat/cargo stats;
  `ShipEconomy` build rows, tech gates, **2 food/hull upkeep**.
- **Naval yard** (capital port): launch any tech-unlocked hull for its row plus
  **one peasant**; it joins or founds the home fleet. Dossier shows Σ FRP.
- **Breaker's yard:** break up one hull (port or sea); one peasant returns, no
  refund; an emptied squadron retires (DR-20261109-01).
- Contested zones fight at turn end **in every region**; only factions **at
  war** engage. Strength `FRP + 0.4·RNG + 0.15·ARM + 0.1·MV`, durability
  `HULL × (1 + ARM/10)`; a 3% edge wins (loser sunk, victor spends half the
  beaten strength); near-equal is a stalemate; port fleets never fight.
- **Rival squadrons** sail their own turn: engage a beatable fleet, threaten the
  best hostile coast, guard its own waters, or cruise home at peace
  (`AiNavalPlanner`); rules stay in `NavalMovement`.

## Deferred (REQ-P2-02)

Home-fleet merge over docking · Patrol/Blockade/Beachhead/Defend ·
interception/retreat/raids · multi-hull markers · ship strength beside land
strength.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/fleet_state.gd` | location, move flag, typed hulls |
| `scripts/rules/ship_stats.gd` | combat / cargo catalog |
| `scripts/rules/ship_economy.gd` | build costs, tech gates, era, upkeep |
| `scripts/rules/fleet_yard.gd` | launch / break up hulls, peasant ledger |
| `scripts/rules/naval_combat.gd` | contested zones, casualties |
| `scripts/rules/naval_movement.gd` | adjacency, validate, `apply_move` |
| `scripts/rules/warp_travel.gd` | passage crossing validation |
| `scripts/map/map_play_warp.gd` | follows a crossing onto the other map |
| `scripts/rules/visibility.gd` | fog reveal + end of turn |
| `scripts/map/ship_layer.gd` | markers, orders, battles |
| `scripts/ai/ai_naval_planner.gd` | rival sail orders |
| `scripts/map/map_play_fleet_ai.gd` | applies rival sails |
| `scripts/map/map_overlay.gd` | destination highlights |
| `scripts/map/fog_layer.gd` | fog texture + fade |
| `scripts/ui/fleet_panel.gd` | dockable dossier, yard orders |
| `scripts/economy/economy_controller.gd` | all-region upkeep |
| `scripts/map_screen.gd` | intents + end-of-turn wiring |

No node deps in rules (`REQ-P3-03`). Orders: `ShipLayer.order` →
`NavalMovement.apply_move`; yard → `FleetYard`; combat → `NavalCombat`.

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Select fleet | click | tap |
| Sail / dock | click highlight | tap highlight |
| Cross passage | click the Passage ring | tap the Passage ring |
| Shipyard | capital dossier → Shipyard | same |
| Cancel | `Esc` | close panel |

## Tests

`test_warp_travel`, `test_naval_movement`, `test_fleet_orders`, `test_visibility`,
`test_ship_stats`, `test_ship_economy`, `test_naval_combat`, `test_fleet_yard`,
`test_ai_naval`, `test_map_screen`.

```bash
gd-tools test --coverage --min 80
```
