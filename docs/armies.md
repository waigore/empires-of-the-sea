# Land armies

**Pillars:** P2, P3, P1, P4, P5. **Wiki:**
[military-armies](https://github.com/waigore/empires-of-the-sea/wiki/military-armies),
[military-units](https://github.com/waigore/empires-of-the-sea/wiki/military-units),
[combat](https://github.com/waigore/empires-of-the-sea/wiki/combat),
[military-generals](https://github.com/waigore/empires-of-the-sea/wiki/military-generals).

## Implemented

- **Roster and drill** (`RegimentCatalog`, `RegimentEconomy`, `ArmyTraining`):
  29 tech-gated regiments into the Home Army.
- **Generals** (`GeneralRoster`, `GeneralBinding`): cap 1→4 by tech, one per
  army, medals 0–4, +1 per win.
- **Combat modifiers** (`ArmyModifiers`): aura 5%/medal; deployment 10
  (12 with Nationalism) + medals; initiative `cavalry×50 + medals×10`;
  feeding 1.0/0.75/0.5; wood 1.5/1.1 defender, 0.9 attacker.
- **Armies** (`ArmyState`): a province per army; one Home Army per crown at its
  capital, never deleted; split/combine needs one province, one owner; one
  march a turn, foreign land must border.
- **Upkeep:** 1–3 food per regiment by era.
- **Combat:** `Σ (FPN + FPM)` over the deployed slice × chevrons × health;
  DEF/9; ratio bands; elimination precedes a flip. A hungrier attacker at
  1.5–4.0 fights 0.6/0.4; mutual ruin restores `ceil(20%)` era-best infantry.
- **Regiment condition** (`RegimentCondition`, DR-20261110-19): health
  (`60 + 10 × DEF`) and chevrons. A break mauls survivors; wounds never destroy
  alone; winners gain a chevron; the wounded recover a quarter a turn.
- **Titles and records** (`RegimentNames`, `RegimentRecord`, DR-20261111-18):
  a period title (unique in its army, kept through split and merge) and the
  engagements and wins tallied in the aftermath hook; printed in the dossier
  and mauled line.
- **Battle honours** (`RegimentRecord`, DR-20261112-02): every survivor of a
  winning side takes the province's name, once, line and reserve alike; the
  dossier prints the two newest (`4 engagements · 3 won · Évora · Lisboa ·
  +2 more`) and the plate adds `Honours — España: Évora added to 3 colours`.
  Display only.
- **Named commanders** (`GeneralNames`, DR-20261112-03): a crown-pool name per
  general, saved (legacy rosters christened on load); the dossier names him
  with his medals.
- **Hospitals** (`HospitalRules`, DR-20261111-12): Field/General (L1–2) on the
  town tile; rest 40%/55%, wear 80%/65%; rivals raise them (DR-20261111-16).
  Wards eat 2 food a level a turn, last in Consumption; an unfed ward rests at
  25% and the summary names it (DR-20261112-04).
- **Re-equipping** (`RegimentUpgrades`): after Movement, before Combat, each
  Great Power's regiments take the newest same-category type its techs unlock;
  Minors follow the leading power, Tribes stay level 1.
- **Attack price** (`ArmyAttackCost`): 100 ducats per attacker, ×0.75 Machinery,
  ×0.85 Military Funding; once per exchange, floor zero.
- **Quick Battle** (`QuickBattle`): three rounds, 3 CP/side;
  aggressive/balanced/defensive. Strength `Σ (FPN + FPM) × chevrons × health` ×
  cohesion. Guns soak fire and cut the fort; sieges split wall/behind
  (`SiegeLanes`); Sortie is its own order ([battle-sim](battle-sim.md)).
- **Unopposed:** an army ending unopposed in hostile or neutral land takes it.

## Deferred (REQ-P2-02)

A predict-the-line preview — [`deferred.md`](deferred.md).

## Architecture

Rules (no nodes, `REQ-P3-03`): `scripts/rules/` `regiment_*`, `army_*`,
`quick_battle*`, `siege_lanes`, `hospital_rules`, `general_*`,
`naval_transport`. Presentation: `map/army_*`, `map/map_play_army*`,
`map/map_play_land_turn`, `ui/army_panel`, `ui/quick_battle_*`, `map_screen`.

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Select / march | click standard, then province | tap both |
| Detach / combine / muster | dossier | dossier |
| Embark / land | dossier | dossier |

## Tests

`test_army_*`, `test_battle_rules`, `test_hospital_rules`.

```bash
gd-tools test --coverage --min 80
```
