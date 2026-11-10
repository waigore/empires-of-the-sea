# Forts and sieges

Walls raised on owned land.

**Pillars:** P2, P3 (rules/view split), P5 (visible outcomes), P1 (dossier).

**Wiki:** [siege-mechanics](https://github.com/waigore/empires-of-the-sea/wiki/siege-mechanics),
[combat](https://github.com/waigore/empires-of-the-sea/wiki/combat) § Battle
Mode, [tech-tree-military](https://github.com/waigore/empires-of-the-sea/wiki/tech-tree-military),
DR-20261110-11 (Quick Battle lanes).

## Implemented

- **Storage:** `ProvinceState.fort_level` 0–3, saved with the world
  (`SaveCodec`); a captured province keeps its walls.
- **Build:** Engineers take `Fort` on a tile of their own crown's province;
  materials are paid on assignment, never refunded. One turn per level (L1 1,
  L2 2, L3 3); a completion lands the ordered level, and a duplicate project
  cannot leap a level or gate. L2 needs Mine Engineering, L3 Modern Forts.
- **Battle mode:** `fort_level == 0` is field, `≥ 1` is siege; every land-battle
  report carries `battle_mode` and `fort_level`.
- **Auto-resolve:** attacking strength is reduced by wall HP (10 / 20 / 30)
  before the ratio band is read, and the band's defender share is scaled by
  1 − damage reduction (0.75 / 0.55 / 0.40). The defender's side adds
  `guns × strength` of its emplaced type (Royal → Heavy → Siege by tech),
  an aggregate bonus, never field regiments.
- **Quick Battle lanes** (`SiegeLanes`): infantry man the wall; the battery and
  horse wait behind it. Firearms (RNG ≥ 2) and artillery hit the wall, only
  artillery reaches behind it, and RNG 1 regiments touch neither. The wall
  scales the blow by its damage reduction unless the garrison sorties (the
  defender's Assault), which lets every regiment strike but sheds the shelter
  for that round. A pike garrison gives no return fire.
- **Gun-loss:** only ranged besiegers silence the battery; every gun lost by
  battle's end lowers the fort one level, whatever the outcome. The plate names
  the gun type, lanes, sorties and breach.
- **Dossier:** the province panel prints the fort and its gun count.

## Costs and numbers

| Level | Fort | Guns | Wall HP | Loss scale | Cost | Turns | Tech |
|------:|------|-----:|--------:|-----------:|------|------:|------|
| 1 | Wood | 1 | 10 | 0.75 | 3 lumber, 3 bronze | 1 | — |
| 2 | Stone | 2 | 20 | 0.55 | 4 lumber, 4 bronze | 2 | Mine Engineering |
| 3 | Modern | 3 | 30 | 0.40 | 5 steel, 5 lumber | 3 | Modern Forts |

## Deferred (REQ-P2-02)

- Town tiles: forts are province-scoped (DR-20261108-04).
- Gates and dedicated sortie orders; province-lane terrain
  (HILL/WOODS/TOWN) stays a Quick Battle deferral.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/fort_rules.gd` | level tables, wall soak, battery, build gates |
| `scripts/rules/siege_lanes.gd` | wall/behind lanes, sortie exposure, lane casualties |
| `scripts/rules/quick_battle_battery.gd` | virtual guns: spawn, hit, fire, downgrade |
| `scripts/world/province_state.gd` | `fort_level` state |
| `scripts/rules/civilian_work.gd` | `build_fort` validation and completion |
| `scripts/rules/army_modifiers.gd` | siege keys per side |
| `scripts/rules/army_combat.gd` | applies the siege keys in one exchange |
| `scripts/ui/province_panel.gd` | fort line in the province dossier |

Node-free (`REQ-P3-03`): the panel reads `fort_level`, combat reads
`FortRules`; both share one table.
