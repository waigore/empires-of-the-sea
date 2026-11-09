# Land armies

Land military: roster, training, armies, generals, marches, battles, capture.

**Pillars:** P2, P3, P1, P4, P5. **Wiki:**
[military-armies](https://github.com/waigore/empires-of-the-sea/wiki/military-armies),
[military-units](https://github.com/waigore/empires-of-the-sea/wiki/military-units),
[combat](https://github.com/waigore/empires-of-the-sea/wiki/combat),
[military-generals](https://github.com/waigore/empires-of-the-sea/wiki/military-generals).

## Implemented

- **Roster and training** (`RegimentCatalog`, `RegimentEconomy`,
  `ArmyTraining`): 29 regiments with FPN/FPM/RNG/DEF/MVR, era, treasury cost,
  material inputs and one peasant from the pool. Tech-gated per
  `tech-tree-military`; new regiments join the Home Army at the capital.
  Cavalry inputs published; others interim.
- **Generals** (`GeneralRoster`, `GeneralBinding`): one per Great Power; cap
  grows 2→4 with `organised_regiments`, `national_bureaucracy`/
  `improved_infantry_tactics`, `nationalism`. One general per attacking then
  defending army each Combat phase, seeded by turn; medals 0–4, +1 per win.
- **Persistence:** saves carry general pools, medals, feeding and leader keys
  (`LeaderCatalog`); a save without pools rebuilds the court from tech caps.
- **Combat modifiers** (`ArmyModifiers`): aura 5%/medal to 20%, deployment 10
  (12 with Nationalism) + medals, initiative `cavalryShare×50 + medals×10`,
  feeding 1.0/0.75/0.5, defender terrain, leader multiplier with fallback
  medals.
- **Armies** (`ArmyState`): one province per army of stable `unit_<n>`
  regiments. One Home Army per faction at its capital, never deleted or
  marching; detach regiments to form field armies. Split/combine needs one
  province and owner; the Home Army is the merge target.
- **Movement:** one march per turn; owned provinces connected through own
  territory are reachable; foreign land must border.
- **Naval transport** (`NavalTransport`, `ArmyTransport`): a field army boards
  a squadron in port (one regiment per hull), sails or crosses a passage, and
  lands on an owned coast beside its zone; boarding/landing spend its march.
  Troops drown with a sunk squadron; hostile shores need a beachhead.
- **Upkeep:** 1–3 food per regiment by category/era, before navy/workers.
- **Combat:** auto-resolve at end of turn. Strength is `Σ (FPN + FPM)` over the
  deployed slice, scaled by the modifiers above; casualties follow the wiki
  ratio bands, weakest-first. Army elimination precedes a flip. Defending
  armies share one side; attackers act in initiative order, ties by one
  deterministic roll. Mutual annihilation restores `ceil(20%)` of the
  defender's start as its era's best infantry.
- **Unopposed:** an army ending in hostile or neutral land with no
  defenders or armed third faction takes it at combat start.
- **Dossier:** composition, strength, food, commander, orders, dock;
  `TROOPS` counts every region.

## Deferred (REQ-P2-02)

Quick Battle, gun-loss downgrade · difficulty · per-regiment medals and
health · minor parity and in-place upgrades.
Sieges read the province fort; see [forts.md](forts.md).

## Architecture

Rules (no nodes, `REQ-P3-03`, all under `scripts/rules/`): `regiment_catalog`,
`regiment_economy`, `army_training`, `army_state`, `general_roster`,
`general_binding`, `army_modifiers`, `army_command`, `army_movement`,
`army_combat`, `naval_transport`. View: `map/army_layer` + `army_marker`,
`map/army_transport`, `map/map_play_armies`, `map/map_play_army_ai`,
`ui/army_panel`, `economy/economy_controller`, `map_screen`.

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Select army | click standard | tap standard |
| March | click highlighted province | tap highlighted province |
| Detach / combine | dossier buttons | dossier buttons |
| Muster | Recruit, then Muster | same |
| Embark / land | dossier buttons | same |
| Cancel | `Esc` | dossier Close |

## Tests

`test_regiment_catalog`, `test_regiment_economy`, `test_army_state`,
`test_army_movement`, `test_army_combat`, `test_army_modifiers`,
`test_generals`, `test_leader_catalog`, `test_army_orders`,
`test_naval_movement`, `test_map_screen_crown_orders`.

```bash
gd-tools test --coverage --min 80
```
