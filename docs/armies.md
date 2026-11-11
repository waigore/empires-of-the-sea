# Land armies

**Pillars:** P2, P3, P1, P4, P5. **Wiki:**
[military-armies](https://github.com/waigore/empires-of-the-sea/wiki/military-armies),
[military-units](https://github.com/waigore/empires-of-the-sea/wiki/military-units),
[combat](https://github.com/waigore/empires-of-the-sea/wiki/combat),
[military-generals](https://github.com/waigore/empires-of-the-sea/wiki/military-generals).

## Implemented

- **Roster and drill** (`RegimentCatalog`, `RegimentEconomy`,
  `ArmyTraining`): 29 tech-gated regiments; recruits join the Home Army.
- **Generals** (`GeneralRoster`, `GeneralBinding`): cap 1→4 by tech, one per
  army, medals 0–4, +1 per win.
- **Combat modifiers** (`ArmyModifiers`): aura 5%/medal, deployment 10
  (12 with Nationalism) + medals, initiative `cavalryShare×50 + medals×10`,
  feeding 1.0/0.75/0.5, wood terrain (defender 1.5/1.1, attacker 0.9).
- **Armies** (`ArmyState`): a province per army; one Home Army per faction at
  its capital, never deleted; detach for field armies; split/combine needs one
  province, one owner, both ashore. One march a turn; own land open, foreign borders.
- **Upkeep:** 1–3 food per regiment by era.
- **Combat:** `Σ (FPN + FPM)` over the deployed slice, scaled by chevrons
  and health; DEF/9 durability; ratio bands; elimination precedes a flip.
  A hungrier attacker at 1.5–4.0 fights 0.6/0.4 and takes nothing; mutual
  annihilation restores `ceil(20%)` of defender start as era-best infantry.
- **Regiment condition** (`RegimentCondition`, DR-20261110-19): health
  (`60 + 10 × DEF`) and chevrons. A break mauls survivors; wounds never destroy
  alone; winners gain a chevron; wounded recover a quarter a turn.
- **Regiment titles and records** (`RegimentNames`, `RegimentRecord`,
  DR-20261111-18): a period title from the crown's pool (unique in its army,
  kept through split, merge and save) and the engagements and wins tallied once
  in the aftermath hook; printed in the dossier, the mauled line and the muster
  toasts. Display only.
- **Named commanders** (`GeneralNames`, DR-20261112-03): each general takes a
  crown-pool name, unique per crown and saved (legacy rosters christened on
  load); the dossier prints him with his medals and a win's despatch credits
  him. Display only.
- **Hospitals** (`HospitalRules`, DR-20261111-12): Field/General
  (L1–2) on the town tile; rest 40%/55%, owner's battle wear 80%/65%. Rivals
  raise them (DR-20261111-16).
- **Re-equipping** (`RegimentUpgrades`): after Movement, before Combat, each
  Great Power's regiments take the newest same-category type its techs unlock;
  Minors follow the leading power, Tribes stay level 1.
- **Attack price** (`ArmyAttackCost`): 100 ducats per attacker, ×0.75 Industrial
  Machinery, ×0.85 Modern Military Funding; once per exchange, floor zero.
- **Quick Battle** (`QuickBattle`): three rounds, 3 CP/side;
  aggressive/balanced/defensive. Strength `Σ (FPN + FPM) × chevrons ×
  health` × cohesion. Guns soak fire and cut the fort; sieges split
  wall/behind (`SiegeLanes`); Sortie is its own order. Plate floats
  `−N`, health, chevrons; [battle-sim.md](battle-sim.md).
- **Unopposed:** an army ending in hostile or neutral land with no armed
  defender takes it.

## Deferred (REQ-P2-02)

Battle honours (DR-20261112-02) pending — [`deferred.md`](deferred.md).

## Architecture

Rules (no nodes, `REQ-P3-03`): `scripts/rules/` `regiment_*`, `army_*`,
`quick_battle*`, `siege_lanes`, `hospital_rules`, `general_*`,
`naval_transport`. Presentation: `map/army_layer`, `map/army_transport`,
`map/map_play_army*`, `map/map_play_land_turn`, `ui/army_panel`,
`ui/quick_battle_*`, `map_screen`.

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Select army | click standard | tap standard |
| March | click highlighted province | tap highlighted province |
| Detach / combine | dossier | dossier |
| Muster | Recruit, then Muster | same |
| Embark / land | dossier | dossier |

## Tests

`test_army_*`, `test_battle_rules`, `test_hospital_rules`,
`test_quick_battle_rules`, `test_siege_depth`, `test_battle_sim`.

```bash
gd-tools test --coverage --min 80
```
