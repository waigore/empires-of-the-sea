# Land armies

**Pillars:** P2, P3, P1, P4, P5. **Wiki:**
[military-armies](https://github.com/waigore/empires-of-the-sea/wiki/military-armies),
[military-units](https://github.com/waigore/empires-of-the-sea/wiki/military-units),
[combat](https://github.com/waigore/empires-of-the-sea/wiki/combat),
[military-generals](https://github.com/waigore/empires-of-the-sea/wiki/military-generals).

## Implemented

- **Roster and training** (`RegimentCatalog`, `RegimentEconomy`,
  `ArmyTraining`): 29 tech-gated regiments with stats, era, cost and
  inputs; recruits join the Home Army at the capital.
- **Generals** (`GeneralRoster`, `GeneralBinding`): one per Great Power, cap
  2→4 by tech; one per army each Combat phase; medals 0–4,
  +1 per win, saved with the court.
- **Combat modifiers** (`ArmyModifiers`): aura 5%/medal to 20%, deployment 10
  (12 with Nationalism) + medals, initiative `cavalryShare×50 + medals×10`,
  feeding 1.0/0.75/0.5, defender terrain, leader multiplier.
- **Armies** (`ArmyState`): one province per army of `unit_<n>` regiments.
  One Home Army per faction at its capital, never deleted; detach regiments
  for field armies. One march per turn; own land is reachable, foreign land
  must border.
- **Naval transport** (`NavalTransport`, `ArmyTransport`): a field army boards
  a squadron in port (one regiment per hull) and lands on an owned coast;
  boarding/landing spend its march; troops drown with a sunk squadron.
- **Upkeep:** 1–3 food per regiment by era, before navy.
- **Combat:** `Σ (FPN + FPM)` over the deployed slice, each regiment scaled by
  chevrons (0–4, ×1.0–1.4) and health; DEF/9 durability; wiki ratio bands,
  weakest-first; elimination precedes a flip. Mutual annihilation restores
  `ceil(20%)` of the defender's start as era-best infantry.
- **Regiment condition** (`RegimentCondition`, DR-20261110-19): every instance
  carries health (`60 + 10 × DEF`) and chevrons, saved with the army. A blow
  that breaks a regiment mauls the survivors; wounds never destroy alone;
  winning survivors gain a chevron (cap 4); the wounded recover a quarter of
  their pool each turn.
- **Quick Battle** (`QuickBattle`): the human's battles run three rounds at
  3 CP a side; the dossier cycles aggressive/balanced/defensive. Virtual guns
  soak fire and can lower the fort; sieges split casualties wall/behind
  (`SiegeLanes`). The plate floats `−N` damage, draws a
  health chip and chevrons per regiment, and ends on losses, mauled men,
  chevrons won and any breach.
- **Minor parity:** Minor Nation regiments match the leading Great Power's era;
  Tribes stay at level 1.
- **Unopposed:** an army ending in hostile or neutral land with no armed
  defenders takes it at combat start.
- **Dossier:** composition, strength, food, commander, orders, dock; rows
  carry stats, chevrons and a health bar while mauled.

## Deferred (REQ-P2-02)

Tactical-stat Quick Battle aggregation (`FPN/FPM`), hospitals, per-regiment
names. Sieges read the province fort; see [forts.md](forts.md).

## Architecture

Rules (no nodes, `REQ-P3-03`, under `scripts/rules/`): `regiment_catalog`,
`regiment_economy`, `army_training`, `army_state`, `regiment_condition`,
`general_roster`, `general_binding`, `army_modifiers`, `army_command`,
`army_movement`, `army_combat`, `army_bands`, `army_garrison`, `quick_battle*`,
`siege_lanes`, `naval_transport`. View: `map/army_layer`, `map/army_transport`,
`map/map_play_armies`, `ui/army_panel`, `ui/quick_battle_*`, `map_screen`.

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
`test_generals`, `test_leader_catalog`, `test_army_orders`,
`test_naval_movement`, `test_quick_battle_rules`,
`test_map_screen_crown_orders`.

```bash
gd-tools test --coverage --min 80
```
