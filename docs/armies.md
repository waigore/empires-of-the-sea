# Land armies

**Pillars:** P2, P3, P1, P4, P5. **Wiki:**
[military-armies](https://github.com/waigore/empires-of-the-sea/wiki/military-armies),
[military-units](https://github.com/waigore/empires-of-the-sea/wiki/military-units),
[combat](https://github.com/waigore/empires-of-the-sea/wiki/combat),
[military-generals](https://github.com/waigore/empires-of-the-sea/wiki/military-generals).

## Implemented

- **Roster and training** (`RegimentCatalog`, `RegimentEconomy`,
  `ArmyTraining`): 29 tech-gated regiments; recruits join the Home Army.
- **Generals** (`GeneralRoster`, `GeneralBinding`): cap 1→4 by tech, every
  crown reconciled at Combat; one per army each phase; medals 0–4, +1 per win.
- **Combat modifiers** (`ArmyModifiers`): aura 5%/medal to 20%, deployment 10
  (12 with Nationalism) + medals, initiative `cavalryShare×50 + medals×10`,
  feeding 1.0/0.75/0.5, terrain (wood: defender 1.5/1.1, attacker 0.9).
- **Armies** (`ArmyState`): one province per army of `unit_<n>` regiments.
  One Home Army per faction at its capital, never deleted; detach for field
  armies; split/combine needs one province, one owner, both ashore. One march
  per turn; own land reachable, foreign must border.
- **Naval transport** (`NavalTransport`, `ArmyTransport`): field army boards a
  port squadron (one regiment per hull) and lands on an owned coast;
  troops drown with a sunk squadron.
- **Upkeep:** 1–3 food per regiment by era, before navy.
- **Combat:** `Σ (FPN + FPM)` over the deployed slice, scaled by chevrons
  and health; DEF/9 durability; ratio bands; elimination precedes a flip.
  Hungrier attacker at 1.5–4.0 fights 0.6/0.4 and takes nothing.
  Mutual annihilation restores `ceil(20%)` of defender start as
  era-best infantry.
- **Regiment condition** (`RegimentCondition`, DR-20261110-19): health
  (`60 + 10 × DEF`) and chevrons. A break mauls survivors; wounds never destroy
  alone; winners gain a chevron; wounded recover a quarter each turn.
- **Hospitals** (`HospitalRules`, DR-20261111-12): Engineer-built Field/General
  (L1–2) on the town tile; rest 40%/55%, owner's battle wear 80%/65%. Rivals
  raise them too (DR-20261111-16).
- **Re-equipping** (`RegimentUpgrades`): after Movement, before Combat, each
  Great Power's regiments take the newest same-category type its techs unlock.
  Minors follow leading power; Tribes, level 1.
- **Attack price** (`ArmyAttackCost`): 100 ducats per Great Power attacker per
  land battle, ×0.75 Industrial Machinery, ×0.85 Modern Military Funding (63);
  once per exchange, floor zero.
- **Quick Battle** (`QuickBattle`): three rounds at 3 CP a side;
  aggressive/balanced/defensive. Strength is `Σ (FPN + FPM) × chevrons ×
  health` × cohesion. Guns soak fire and lower the fort;
  sieges split wall/behind (`SiegeLanes`), scale by ground
  (HILL/WOODS/TOWN/MARSH), three gates; Sortie is its own order. Plate floats
  `−N`, health, chevrons. Simulator: [battle-sim.md](battle-sim.md).
- **Unopposed:** army ending in hostile or neutral land with no armed
  defender takes it.
- **Dossier:** composition, strength, food, commander, orders, dock,
  condition.

## Deferred (REQ-P2-02)

Regiment names ([`deferred.md`](deferred.md)).

## Architecture

Rules (no nodes, `REQ-P3-03`, under `scripts/rules/`): `regiment_catalog`,
`regiment_economy`, `regiment_upgrades`, `army_training`, `army_state`,
`regiment_condition`, `hospital_rules`, `general_roster`, `general_binding`, `army_modifiers`,
`army_command`, `army_movement`, `army_combat`, `army_attack_cost`,
`army_bands`, `army_garrison`, `quick_battle*`, `siege_lanes`,
`naval_transport`. `map/army_layer`, `map/army_transport`,
`map/map_play_armies`, `map/map_play_army_muster`, `map/map_play_land_turn`,
`ui/army_panel`, `ui/quick_battle_*`, `map_screen`.

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Select army | click standard | tap standard |
| March | click highlighted province | tap highlighted province |
| Detach / combine | dossier buttons | dossier buttons |
| Muster | Recruit, then Muster | same |
| Embark / land | dossier buttons | same |

## Tests

`test_regiment_catalog`, `test_regiment_economy`, `test_army_state`,
`test_army_movement`, `test_army_combat`, `test_army_modifiers`,
`test_army_field_rules`, `test_hospital_rules`, `test_generals`,
`test_army_orders`, `test_naval_movement`, `test_quick_battle_rules`,
`test_siege_depth`, `test_battle_sim`, `test_map_screen_crown_orders`.

```bash
gd-tools test --coverage --min 80
```
