# Forts and sieges

**Pillars:** P2, P3, P5, P1. **Wiki:**
[siege-mechanics](https://github.com/waigore/empires-of-the-sea/wiki/siege-mechanics),
[combat](https://github.com/waigore/empires-of-the-sea/wiki/combat) § Battle Mode,
DR-20261110-27.

## Implemented

- **Storage / build:** `ProvinceState.fort_level` 0–5, saved; a captured
  province keeps its walls. An Engineer's `Fort` project rises on the town tile
  (`FortRules.site_tile`), materials at assign.
- **Start walls** (issue #1314): every Old World Great Power or Minor province
  opens at Wood, its capital at Stone; New World and colonies stay 0. A Great
  Power's fort tech lifts its own capital one step once (Modern 3, Bastion 4,
  Star 5); a siege downgrade is not restored.
- **Unopposed capture** is open ground only. An empty walled province is
  **stormed**: beat wall HP + the battery (`FortRules.storm_threshold`, the
  **defender's** Royal → Heavy → Siege line); each whole 10 past it
  costs a regiment, weakest first. A crossing storm is a battle: survivors rise
  a chevron, take the field on their colours and carry the wear
  (DR-20261123-24). Every storm pays the land's attack price — repelled or
  crossed, once per attacker (DR-20261123-22); an unopposed walk-in pays
  nothing. Stormers follow the chain; a repulse names the wall and leaves it
  for the next.
- **Battle mode:** 0 field, `≥ 1` siege. **Scaling:** 40 × level wall HP, level
  guns, 10% × level off a blow; the opening muster (21) cannot storm a Wood fort.
- **Auto-resolve:** wall HP soaks attack; the defender's share is scaled by
  1 − damage reduction and adds `guns × strength` of its emplaced type.
- **Quick Battle** (`SiegeLanes`): infantry man the wall, horse and guns wait
  behind; RNG ≥ 2 hits the wall, only artillery reaches behind. Gates: three,
  each after `ceil(wall HP / 3)` casualties; a breach opens the behind lane.
  Grounds: `SiegeGround`.
- **The wall reads itself** (`WallRead`, DR-20261120-06, DR-20261123-20): the
  sheet's **Wall** row, the observatory and a march name its soak, spare share
  and storm — `51` on the crown's own ground, `51–59` on another court's, whose
  battery is unread.

## Costs and numbers

| Level | Fort | Guns | Wall HP | Soak off a blow | Cost | Turns | Tech |
|------:|------|-----:|--------:|----------------:|------|------:|------|
| 1 | Wood | 1 | 40 | 10% | 3 lumber, 3 bronze | 1 | — |
| 2 | Stone | 2 | 80 | 20% | 4 lumber, 4 bronze | 2 | Mine Engineering |
| 3 | Modern | 3 | 120 | 30% | 5 steel, 5 lumber | 3 | Modern Forts |
| 4 | Bastion | 4 | 160 | 40% | 5 steel, 4 lumber, 3 bronze | 3 | Bastion Forts |
| 5 | Star | 5 | 200 | 50% | 6 steel, 6 lumber | 4 | Star Forts |

## Architecture

| File | Role |
|------|------|
| `scripts/rules/fort_rules.gd` | tables, wall soak, storm ladder, town site |
| `scripts/rules/fort_capital.gd` | start walls, one-shot capital step |
| `scripts/rules/siege_lanes.gd` | wall/behind lanes, terrain, gates, sortie |
| `scripts/rules/quick_battle_battery.gd`, `auto_siege.gd` | guns, counter-battery, downgrade |
| `scripts/rules/civilian_work.gd` | `build_fort` target and completion |
| `scripts/ui/battle_plate*.gd`, `quick_battle_field.gd` | wall, gates, ground |

## Tests

`test_battle_rules`.
