# Fleets and naval combat

Fog, cargo, battles, raids:
[naval-missions.md](naval-missions.md).

**Pillars:** P2, P3, P1, P4.

**Wiki:** [ships-and-naval](https://github.com/waigore/empires-of-the-sea/wiki/ships-and-naval),
[fog-and-exploration](https://github.com/waigore/empires-of-the-sea/wiki/fog-and-exploration).

## Implemented

- Sea zone or port, never both; one roster/region.
- **One move / turn:** S↔S; undock; dock at an owned port; a warp crosses.
- A new zone reveals water + **coastal ring**; fog decays.
- Hulls are instances (`ship_<n>` + type); `ShipStats` FRP/RNG/ARM/HULL/MV;
  `ShipEconomy` builds with tech gates, **2 food upkeep**.
- **Named hulls** (`ShipNames`): period, unique, kept through save and merge
  (DR-20261111-07).
- **Yard:** launch for its row + **one peasant**; lands next turn; break-up
  returns a peasant, no refund (DR-20261109-01).
- **Home cargo:** merchant **holds** (1/turn) cap imports; a seat harbour grants
  one; GPs start with ≥1 warship (DR-20261109-03).
- **Home merge:** seat dock or dossier **Join the home fleet**; ids, names,
  passengers keep.
- **Home sortie** (DR-20261109-17): the home squadron may sail (spends
  move/holds); colonists ride one per hull.
- **Split a squadron** (DR-20261116-12): the dossier's **Split the squadron**
  drawer detaches one hull into a command of her own in the same station.
- Contested zones fight at turn end: `FRP + 0.4·RNG + 0.15·ARM + 0.1·MV`;
  durability `HULL × (1 + ARM/10)`; a 3% edge wins, the loser retreats.
- **Markers:** escorts, hull badge, strength; a rival `*` / `???` until watched
  (DR-20261113-20).
- **Stations:** Patrol, Blockade, Defend, Beachhead; one station or move/turn
  (DR-20261109-13/16); raids sink one merchant hull (DR-20261111-17).
- **Army transport** (`NavalTransport`): board (one regiment/hull), sail or
  cross, land on an owned coast; troops drown with a sunk hull.
- **Beachhead:** mark a hostile coast (spends the move); the army lands next;
  unused markers lapse.

**The crown's navy** (DR-20261115-14): the muster door (`N`) lists each hull;
**Visit** frames her.

**The sea reading** (`H`, DR-20261115-17; `SeaSurvey`/`SeaLens`): the zones the
crown's sail sees — hulls, strength, station, rival.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/{fleet_state,fleet_missions,ship_stats,ship_economy}.gd` | location, stations, combat, build |
| `scripts/rules/{naval_strength,fleet_yard,trade_cargo,fleet_sortie,fleet_home_merge}.gd` | strength, yard, cargo, sortie, home merge |
| `scripts/rules/{naval_*,warp_travel}.gd` | battles, moves, stations, raids |
| `scripts/rules/{naval_transport,civilian_voyage}.gd`, `scripts/map/{army_transport,map_play_beachhead,civilian_voyage_map}.gd` | board, land, beachhead |
| `scripts/ai/ai_naval_planner.gd`, `scripts/map/{map_play_fleet_ai,map_play_fleet_missions,map_play_raids}.gd` | rival sorties, stations, raids |
| `scripts/map/{map_play_fleets,map_play_fleet_intel,map_play_fleet_yard,map_play_fleet_split}.gd` | sail orders, the crown's watch, shipyard, split |
| `scripts/map/{ship_layer,ship_markers,fleet_rosters,map_overlay,map_play_warp,fog_layer}.gd` | orders, markers, rosters, fog |
| `scripts/ui/{fleet_panel,fleet_*_section,fleet_split_block,panel_dock}.gd` | dossier, strength, passengers, stations, split |
| `scripts/rules/naval_ledger.gd`, `scripts/ui/naval_ledger_*.gd` | the navy, hull by hull |
| `scripts/economy/economy_controller.gd`, `scripts/map_screen.gd` | upkeep, intents |

No node deps (`REQ-P3-03`).

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Select fleet | click | tap |
| Sail, dock, passages | highlight | same |
| Join home | dossier button | same |
| Station | dossier button | same |
| Land troops | dossier button | same |
| Colonists | dossier **PASSENGERS** | same |
| Beachhead | dossier coast button | same |
| Shipyard | capital | same |
| Navy | roll's **Navy ›**, `N` | same |

## Deferred

None.

## Tests

`test_naval_rules`, `test_fleet_orders`, `test_ledgers`, `test_map_screen`.

```bash
gd-tools test --coverage --min 80
```
