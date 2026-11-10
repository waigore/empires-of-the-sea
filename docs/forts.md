# Forts and sieges

**Pillars:** P2, P3, P5, P1. **Wiki:**
[siege-mechanics](https://github.com/waigore/empires-of-the-sea/wiki/siege-mechanics),
[combat](https://github.com/waigore/empires-of-the-sea/wiki/combat) § Battle Mode,
DR-20261110-27.

## Implemented

- **Storage:** `ProvinceState.fort_level` 0–3, saved; a captured province keeps
  its walls.
- **Build:** Engineers take `Fort`; the project rises on the province's **town
  tile** wherever the engineer stands (`FortRules.site_tile`; legacy maps keep
  the ordered tile). Materials paid at assign; one turn per level; duplicates
  cannot leap a level or gate. L2 Mine Engineering, L3 Modern Forts.
- **Battle mode:** `fort_level == 0` is field, `≥ 1` is siege; reports carry
  both.
- **Auto-resolve:** wall HP (10/20/30) soaks attack before the ratio band; the
  defender's share is scaled by 1 − damage reduction (0.75/0.55/0.40) and adds
  `guns × strength` of its emplaced type. The besieging train silences a piece
  per gun's weight of deployed field artillery (whole pieces only); the last
  gun drops the fort a level even when repelled (DR-20261110-22).
- **Quick Battle lanes** (`SiegeLanes`): infantry man the wall, horse and guns
  wait behind. RNG ≥ 2 hits the wall, only artillery reaches behind, RNG 1
  touches neither. The wall scales the blow unless the garrison sorties; a
  sortie exposes it but lets every regiment strike. A pike garrison gives no
  return fire; one blow bleeds no more than the deployed slice.
- **Ground:** HILL on hills/mountains, WOODS in forest, MARSH in swamp, TOWN
  where a fort rings open ground. Volleys and assaults are weaker into broken
  ground; entrenching is surer in HILL/WOODS/TOWN.
- **Gates:** three; each falls after `ceil(wall HP / 3)` wall casualties. A
  breach ends the wall's reduction and opens the behind lane in the share of
  gates lost.
- **Sortie:** the defender's own order, not an Assault on its own wall. Every
  regiment strikes, the garrison is exposed; a firearmless garrison sallies.
- **Gun-loss:** a standing gun spends the blow before the lanes; each gun lost
  drops the fort one level whatever the outcome. The plate names guns, lanes,
  gates and breach.
- **Dossier:** the province panel prints the fort.

## Costs and numbers

| Level | Fort | Guns | Wall HP | Loss scale | Cost | Turns | Tech |
|------:|------|-----:|--------:|-----------:|------|------:|------|
| 1 | Wood | 1 | 10 | 0.75 | 3 lumber, 3 bronze | 1 | — |
| 2 | Stone | 2 | 20 | 0.55 | 4 lumber, 4 bronze | 2 | Mine Engineering |
| 3 | Modern | 3 | 30 | 0.40 | 5 steel, 5 lumber | 3 | Modern Forts |

## Architecture

| File | Role |
|------|------|
| `scripts/rules/fort_rules.gd` | tables, wall soak, battery, town site, gates |
| `scripts/rules/siege_lanes.gd` | wall/behind lanes, terrain, gates, sortie |
| `scripts/rules/quick_battle_battery.gd` | virtual guns and fort downgrade |
| `scripts/rules/auto_siege.gd` | auto-resolve counter-battery and downgrade |
| `scripts/rules/civilian_work.gd` | `build_fort` target and completion |
| `scripts/ui/battle_plate.gd`, `quick_battle_field.gd` | wall, gates, ground |
| `scripts/rules/battle_scenario.gd` | sandbox battle for [battle-sim.md](battle-sim.md) |

Node-free: dossier reads `fort_level` (`REQ-P3-03`).

## Tests

`test_fort_rules`, `test_siege_depth`, `test_quick_battle_rules`,
`test_battle_sim`.
