# Forts and sieges

**Pillars:** P2, P3, P5, P1. **Wiki:**
[siege-mechanics](https://github.com/waigore/empires-of-the-sea/wiki/siege-mechanics),
[combat](https://github.com/waigore/empires-of-the-sea/wiki/combat) § Battle Mode,
DR-20261110-27.

## Implemented

- **Storage:** `ProvinceState.fort_level` 0–3, saved; capture keeps walls.
- **Build:** Engineers take `Fort` on the province **town tile**
  (`FortRules.site_tile`; legacy maps keep the ordered tile). Materials at
  assign; one turn per level; no leap or gate. L2 Mine Engineering, L3 Modern
  Forts.
- **Capitals:** every Old World capital opens at Wood (Great Power and Minor).
  Mine Engineering / Modern Forts lifts a Great Power capital to L2 / L3 once;
  a siege downgrade is not restored.
- **Battle mode:** 0 field, `≥ 1` siege; reports carry both.
- **Auto-resolve:** wall HP (10/20/30) soaks attack before the ratio band;
  defender share × (1 − damage reduction 0.75/0.55/0.40) plus
  `guns × strength`. Train silences a piece per gun weight (DR-20261110-22).
- **Quick Battle lanes** (`SiegeLanes`): infantry on the wall; horse and guns
  behind. RNG ≥ 2 hits wall; only artillery reaches behind; RNG 1 neither.
  Wall scales the blow unless a sortie exposes the garrison for every
  regiment. Pike gives no return; a blow bleeds at most the deployed slice.
- **Ground** (`SiegeGround`): HILL hills/mountains, WOODS forest, MARSH swamp,
  TOWN where a fort rings open ground. Volleys/assaults weaker into broken
  ground; entrenching surer there.
- **Gates** (`SiegeGates`): three; each falls after `ceil(wall HP / 3)`
  casualties. A breach ends reduction and opens the behind lane in the share
  lost.
- **Sortie:** defender order, not Assault. Every regiment strikes, garrison
  exposed; a firearmless garrison sallies.
- **Gun-loss:** a gun spends the blow before lanes; empty blow buys nothing;
  last gun still drops one level. Plate names guns, lanes, gates.
- **The wall reads itself** (`WallRead`, DR-20261120-06): province **Wall** row
  prints `10 wall hp · 25% off a blow` by level (empty on open ground);
  observatory sheet the same; march into a rival walled province reads e.g.
  `The army marches on Badajoz — a wood fort stands: 10 wall hp, 1 emplaced
  gun, 25% off a blow.` Figures from `FortRules.wall_soak` / `loss_scale`;
  nothing predicted.

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
