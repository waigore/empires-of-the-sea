# Land armies

**Pillars:** P2, P3, P1, P4, P5. **Wiki:**
[military-armies](https://github.com/waigore/empires-of-the-sea/wiki/military-armies),
[military-units](https://github.com/waigore/empires-of-the-sea/wiki/military-units),
[combat](https://github.com/waigore/empires-of-the-sea/wiki/combat),
[military-generals](https://github.com/waigore/empires-of-the-sea/wiki/military-generals).

## Implemented

- **Roster** (`RegimentCatalog`, `RegimentEconomy`, `ArmyTraining`): 29
  tech-gated regiments.
- **Generals** (`GeneralRoster`, `GeneralBinding`): cap 1→4 by tech, one per
  army; medals 0–4, +1 a win.
- **Combat modifiers** (`ArmyModifiers`): aura 5%/medal; deployment 10
  (12 with Nationalism) + medals; initiative `cavalry×50 + medals×10`;
  feeding 1.0/0.75/0.5; wood 1.5/1.1 defender, 0.9 attacker.
- **Armies** (`ArmyState`): one province per army; one Home Army per crown at
  its capital, never deleted; split/combine needs one province and owner; one
  march a turn, foreign land bordering. **Dismiss** sheds a regiment (or all),
  a peasant each, no refund; an emptied army retires (DR-20261109-01). A stranded
  host walks home, naming its harbour (DR-20261121-15, DR-20261122-07/-09).
- **Upkeep:** 1–3 food a regiment, by era.
- **Rations** (`ArmyRationRead`, DR-20261124-02): the dossier names the share fed
  and the morale the field reads (wiki: combat § Feeding modifiers).
- **Combat:** `Σ (FPN + FPM)` over the deployed slice × chevrons × health ×
  citation; DEF/9; ratio bands; elimination precedes a flip; mutual ruin
  restores `ceil(20%)` infantry.
- **Condition** (`RegimentCondition`, DR-20261110-19): health (`60 + 10 × DEF`)
  and chevrons; a break mauls survivors, winners gain a chevron.
- **Titles** (`RegimentNames`, `RegimentRecord`, DR-20261111-18): one per army,
  kept through split/merge; the dossier renames it (DR-20261113-05).
- **Colours** (`RegimentRecord`, `RegimentDecorations`, DR-20261112-02/-10,
  DR-20261113-04): winners take the province once; a survivor keeps eight
  despatches, a mauled win a **citation** (`cited` +5%, `laurelled` +10%);
  decorated colours lead and fall last.
- **The orders** (`MapPlayArmyPick`, DR-20261120-10; `MapPlayArmyOrdersPick`,
  DR-20261121-14; `MapPlayForceCounsel`, DR-20261121-17/22-03): the order prints
  on its dossier, the muster roll and THE CROWN'S ARMY (`ArmyLedger`,
  DR-20261116-16), or the gate; named rows wear `▸` with its legend (DR-20261122-05/23-03).
- **The drill yard's pick** (`MapPlayMusterPick`, DR-20261121-03/22-12): the
  muster block prints the line the published muster would raise (or its gate),
  marked `▸` (DR-20261123-08).
- **Named commanders** (`GeneralNames`, DR-20261112-03): one pooled name each.
- **Hospitals** (`HospitalRules`, DR-20261111-12): Field/General (L1–2) on
  town tiles; rest 40%/55%, wear 80%/65%; wards eat 2 food a level, unfed 25%
  (DR-20261112-04).
- **Re-equipping** (`RegimentUpgrades`): the newest same-category type its
  techs unlock; Minors follow the leading power, Tribes 1.
- **Attack price** (`ArmyAttackCost`, DR-20261124-11): 100 ducats an attacker,
  ×0.75 Machinery, ×0.85 Funding; the dossier names it (`AttackPriceRead`).
- **Boarding** (`DeckRead`, DR-20261124-14): the press names the deck, or stands
  disabled with the rules' refusal (ships-and-naval).
- **Quick Battle** (`QuickBattle`): three rounds, 3 CP/side, three stances;
  strength × cohesion. Guns soak fire, cut the fort; sieges split
  wall/behind (`SiegeLanes`).
- **Unopposed:** an army alone in hostile or neutral land takes it.
## Deferred (REQ-P2-02)

All in [`deferred.md`](deferred.md).

## Architecture

Rules (no nodes, `REQ-P3-03`): `scripts/rules/` `regiment_*`, `army_*`,
`quick_battle*`, `siege_lanes`, `hospital_rules`, `hospital_train`,
`general_*`, `naval_transport`, `deck_read`. Presentation: `map/army_*`, `map/map_play_army*`,
`map_play_muster_pick*`, `map_play_land_turn`, `ui/army_panel`,
`ui/quick_battle_*`, `map_screen`.

```text
ArmyState        roster ids + type per instance, ownership and place
RegimentRecord   christens, re-equips and releases each instance's store
ArmyLayer        hands a crown over in place, then writes stored rosters back
```

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Select / march | click standard, then province | tap |
| Detach / combine / muster / rename | dossier | dossier |
| Embark / land | dossier | dossier |

## Tests

`test_army_*`, `test_a_battle_rules`.

```bash
gd-tools test --coverage --min 80
```
