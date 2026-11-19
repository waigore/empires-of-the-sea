# Fleets and naval combat

Fog, cargo, battles, raids:
[naval-missions.md](naval-missions.md).

**Pillars:** P2, P3, P1, P4.

**Wiki:** [ships-and-naval](https://github.com/waigore/empires-of-the-sea/wiki/ships-and-naval),
[fog-and-exploration](https://github.com/waigore/empires-of-the-sea/wiki/fog-and-exploration).

## Implemented

- Sea zone or port, never both; one roster/region.
- **One move/turn:** S↔S; undock; dock at an owned port; warp crosses.
- A new zone reveals water + **coastal ring**; fog decays.
- Hulls are instances (`ship_<n>` + type), **named** (`ShipNames`, kept through
  save/merge); `ShipStats` FRP/RNG/ARM/HULL/MV; **2 food upkeep** (DR-20261111-07).
- **Yard:** launch + **one peasant**; lands next; break-up returns a peasant
  (DR-20261109-01); each row names her line (DR-20261117-15); a flown hull
  needs no tech (#484).
- **Home cargo:** merchant **holds** cap imports; a seat harbour grants one
  **trade** hold (DR-20261109-03, #484).
- **Home merge:** seat dock or dossier **Join the home fleet**; ids, names,
  passengers keep.
- **Home sortie** (DR-20261109-17): the home squadron may sail (spends
  move/holds); one colonist per hull; **Take all ready** mans a whole berth in
  one press (DR-20261119-18).
- **Split / combine** (DR-20261116-12/13): the dossier detaches one hull, or
  folds it into another of yours in the same station.
- Contested zones fight at the close: `FRP + 0.4·RNG + 0.15·ARM + 0.1·MV`;
  durability `HULL × (1 + ARM/10)`; a 3% edge wins, the loser retreats.
- **Markers:** escorts, hull badge, strength on the selection; a rival `*`
  until watched (DR-20261113-20).
- **One station:** the crown's ≤3 fan out, the rest and every rival stack; a
  tap cycles them; a merge re-reads (DR-20261119-08/17).
- **Opening muster:** every Great Power's hulls ride one home fleet at its
  capital (#1043).
- **Stations:** Patrol, Blockade, Defend, Beachhead; one station or move/turn
  (DR-20261109-13/16); raids sink one merchant hull (DR-20261111-17).
- **Army transport** (`NavalTransport`): board one regiment/hull, sail or cross,
  land on an owned coast; troops drown with the hull.
- **Beachhead:** mark a hostile coast (spends the move); lands next; lapses.

**Navy** (`N`, DR-20261115-14): the muster door lists each hull;
**Visit** frames.

(`H`, DR-20261115-17): zones the crown's sail sees.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/{fleet_state,fleet_missions,ship_stats,ship_economy}.gd` | location, stations, build |
| `scripts/rules/{naval_strength,fleet_yard,trade_cargo,fleet_sortie,fleet_home_merge,fleet_combine}.gd` | strength, yard, cargo, sortie, home merge, combine |
| `scripts/rules/{naval_*,warp_travel}.gd` | battles, moves, stations, raids |
| `scripts/rules/{naval_transport,naval_deck,civilian_voyage}.gd`, `scripts/map/{army_transport,map_play_beachhead,civilian_voyage_map}.gd` | board, land, beachhead, deck |
| `scripts/ai/ai_naval_planner.gd`, `scripts/map/{map_play_fleet_ai,map_play_fleet_missions,map_play_raids}.gd` | rival sorties, stations, raids |
| `scripts/map/{map_play_fleets,map_play_fleet_intel,map_play_fleet_yard,map_play_fleet_split,map_play_fleet_combine}.gd` | sail orders, the crown's watch, shipyard, split, combine |
| `scripts/map/{ship_layer,ship_markers,fleet_lanes,fleet_rosters,map_overlay,map_play_warp,fog_layer}.gd` | orders, markers, rows, rosters, fog |
| `scripts/ui/{fleet_panel,fleet_*_section,fleet_*_block,panel_dock}.gd` | dossier, strength, passengers, stations, split, combine |
| `scripts/rules/naval_ledger.gd`, `scripts/ui/naval_ledger_*.gd` | the navy, hull by hull |
| `scripts/economy/economy_controller.gd`, `scripts/map_screen.gd` | upkeep, intents |

No node deps (`REQ-P3-03`).

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Select fleet | click | tap |
| Sail, dock, passages | highlight | same |
| Join home, combine, station, land, beachhead | dossier button | same |
| Colonists | dossier **PASSENGERS** | same |
| Shipyard | capital | same |
| Navy | roll's **Navy ›**, `N` | same |

## Deferred

None — [`deferred.md`](deferred.md).

## Tests

`test_naval_rules`, `test_fleet_orders`, `test_ledgers`, `test_map_screen`.

```bash
gd-tools test --coverage --min 80
```
