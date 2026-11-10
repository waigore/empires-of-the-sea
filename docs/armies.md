# Land armies

Roster, training, armies, generals, marches, battles, capture.

**Pillars:** P2, P3, P1, P4, P5. **Wiki:**
[military-armies](https://github.com/waigore/empires-of-the-sea/wiki/military-armies),
[military-units](https://github.com/waigore/empires-of-the-sea/wiki/military-units),
[combat](https://github.com/waigore/empires-of-the-sea/wiki/combat),
[military-generals](https://github.com/waigore/empires-of-the-sea/wiki/military-generals).

## Implemented

- **Roster and training** (`RegimentCatalog`, `RegimentEconomy`,
  `ArmyTraining`): 29 tech-gated regiments with FPN/FPM/RNG/DEF/MVR, era, cost,
  inputs; recruits join the Home Army.
- **Generals** (`GeneralRoster`, `GeneralBinding`): one per Great Power, cap
  2→4 by tech; one per army each Combat phase, seeded by turn; medals 0–4.
- **Persistence:** saves carry general pools, medals, feeding and leader keys.
- **Combat modifiers** (`ArmyModifiers`): medal aura to 20%, deployment 10
  (12 with Nationalism) + medals, initiative `cavalryShare×50 + medals×10`,
  feeding 1.0/0.75/0.5, terrain, leader.
- **Armies** (`ArmyState`): one province per army of `unit_<n>` regiments; one
  Home Army per faction at its capital, never deleted or marching. Split or
  combine needs one province and owner; the Home Army is the merge target.
- **Movement:** one march per turn; own connected territory is reachable;
  foreign land must border.
- **Naval transport** (`NavalTransport`, `ArmyTransport`): a field army boards
  a squadron in port (one regiment per hull) and lands on an owned coast;
  troops drown with a sunk squadron, and hostile shores need a beachhead.
- **Upkeep:** 1–3 food per regiment by era, before navy.
- **Combat:** `Σ (FPN + FPM)` over the deployed slice, scaled by modifiers;
  wiki ratio bands, weakest-first; elimination precedes a flip; initiative
  orders attackers. Mutual annihilation restores `ceil(20%)` as era-best
  infantry.
- **Re-equipping** (`RegimentUpgrades`): after Movement, before Combat, each
  Great Power's regiments take the newest same-category type its techs unlock —
  instance, army and province kept, no extra treasury or materials. Minors
  follow the leading power's era; Tribes stay at level 1.
- **Attack price** (`ArmyAttackCost`): 100 ducats per Great Power attacker per
  land battle, ×0.75 Industrial Machinery, ×0.85 Modern Military Funding (63
  both); charged once per exchange off the attacker's ledger, floored at zero,
  printed in the despatch.
- **Quick Battle** (`QuickBattle`): the human's battles run three rounds at 3
  CP a side; the dossier cycles aggressive/balanced/defensive. Guns soak fire
  and can lower the fort; sieges route casualties through `SiegeLanes`.
- **Unopposed:** an army ending in hostile or neutral land with no defenders or
  armed third faction takes it at combat start.
- **Dossier:** composition, strength, food, commander, orders, dock; `TROOPS`
  counts every region.

## Deferred (REQ-P2-02)

Regiment medals and health. Sieges read the province fort; see
[forts.md](forts.md).

## Architecture

Rules (no nodes, `REQ-P3-03`, all under `scripts/rules/`): `regiment_catalog`,
`regiment_economy`, `regiment_upgrades`, `army_training`, `army_state`,
`general_roster`, `general_binding`, `army_modifiers`, `army_command`,
`army_movement`, `army_combat`, `army_attack_cost`, `quick_battle`,
`quick_battle_actions`, `quick_battle_battery`, `siege_lanes`,
`naval_transport`. View: `map/army_layer` + `army_marker`,
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

## Tests

`test_regiment_catalog`, `test_regiment_economy`, `test_army_state`,
`test_army_movement`, `test_army_combat`, `test_army_modifiers`,
`test_army_field_rules`, `test_generals`, `test_leader_catalog`,
`test_army_orders`, `test_naval_movement`, `test_quick_battle_rules`,
`test_map_screen_crown_orders`.

```bash
gd-tools test --coverage --min 80
```
