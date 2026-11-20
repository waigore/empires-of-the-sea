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
- **Capitals:** every Old World capital opens at Wood, advanced starts included
  (Great Power and Minor). A Great Power's Mine Engineering / Modern Forts lifts
  its own capital to L2 / L3 once; a siege downgrade is not restored.
- **Battle mode:** 0 field, `≥ 1` siege; reports carry both.
- **Auto-resolve:** wall HP (10/20/30) soaks attack before the ratio band; the
  defender's share is scaled by 1 − damage reduction (0.75/0.55/0.40) and adds
  `guns × strength` of its emplaced type. The train silences a piece per gun's
  weight of artillery (whole pieces; DR-20261110-22).
- **Quick Battle lanes** (`SiegeLanes`): infantry man the wall, horse and guns
  wait behind. RNG ≥ 2 hits the wall, only artillery reaches behind, RNG 1
  touches neither. The wall scales the blow unless the garrison sorties; a
  sortie exposes it but lets every regiment strike. A pike garrison gives no
  return fire; a blow bleeds no more than the deployed slice.
- **Ground** (`SiegeGround`): HILL on hills/mountains, WOODS in forest, MARSH in
  swamp, TOWN where a fort rings open ground. Volleys and assaults are weaker
  into broken ground; entrenching is surer there.
- **Gates** (`SiegeGates`): three; each falls after `ceil(wall HP / 3)`
  casualties. A breach ends the reduction and opens the behind lane in the
  share lost.
- **Sortie:** the defender's own order, not an Assault. Every
  regiment strikes, the garrison exposed; a firearmless garrison sallies.
- **Gun-loss:** a gun spends the blow before the lanes; an empty blow buys
  nothing, and the last gun still drops the fort one level. The plate names
  guns, lanes and gates.

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
| `scripts/rules/fort_capital.gd` | capital grant, one-shot tech step |
| `scripts/rules/siege_lanes.gd` | wall/behind lanes, terrain, gates, sortie |
| `scripts/rules/quick_battle_battery.gd` | virtual guns, downgrade |
| `scripts/rules/auto_siege.gd` | counter-battery, downgrade |
| `scripts/rules/civilian_work.gd` | `build_fort` target and completion |
| `scripts/ui/battle_plate*.gd`, `quick_battle_field.gd` | wall, gates, ground |
| `scripts/rules/battle_scenario.gd` | sandbox for [battle-sim.md](battle-sim.md) |


## Tests

`test_battle_rules`.
