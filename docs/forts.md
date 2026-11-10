# Forts and sieges

**Pillars:** P2, P3 (rules/view split), P5 (visible outcomes), P1 (dossier).

**Wiki:** [siege-mechanics](https://github.com/waigore/empires-of-the-sea/wiki/siege-mechanics),
[combat](https://github.com/waigore/empires-of-the-sea/wiki/combat) § Battle
Mode, [tech-tree-military](https://github.com/waigore/empires-of-the-sea/wiki/tech-tree-military),
DR-20261110-11.

## Implemented

- **Storage:** `ProvinceState.fort_level` 0–3, saved (`SaveCodec`); a captured
  province keeps its walls.
- **Build:** Engineers take `Fort` on a tile of their own province; materials
  are paid on assignment. One turn per level; a duplicate project cannot leap a
  level or gate. L2 needs Mine Engineering, L3 Modern Forts.
- **Battle mode:** `fort_level == 0` is field, `≥ 1` is siege; every report
  carries `battle_mode` and `fort_level`.
- **Auto-resolve:** attacking strength falls by wall HP (10 / 20 / 30) before
  the ratio band; the defender's share is scaled by 1 − damage reduction
  (0.75 / 0.55 / 0.40). The defender adds `guns × strength` of its emplaced
  type (Royal → Heavy → Siege).
- **Quick Battle lanes** (`SiegeLanes`): infantry man the wall, horse and guns
  wait behind. Firearms (RNG ≥ 2) and artillery hit the wall; only artillery
  reaches behind. The wall scales the blow unless the garrison sorties
  (Assault), which lets every regiment strike but sheds cover. A pike garrison
  gives no return fire; one blow bleeds no more than the deployed slice, the
  wall drawing first.
- **Gun-loss:** ranged besiegers reach the battery, and a standing gun spends
  the blow before the lanes; each gun lost drops the fort one level whatever
  the outcome. The plate names guns, lanes, sorties and breach.
- **Auto-resolve gun-loss:** the besieging train answers the battery — one
  emplaced piece per gun's weight of deployed field artillery, whole pieces
  only. Standing guns alone add strength; the last gun drops the fort a level
  even in a repulsed attack (DR-20261110-22). A silenced-battery medallion
  marks the toast.
- **Dossier:** the province panel prints fort and guns.

## Costs and numbers

| Level | Fort | Guns | Wall HP | Loss scale | Cost | Turns | Tech |
|------:|------|-----:|--------:|-----------:|------|------:|------|
| 1 | Wood | 1 | 10 | 0.75 | 3 lumber, 3 bronze | 1 | — |
| 2 | Stone | 2 | 20 | 0.55 | 4 lumber, 4 bronze | 2 | Mine Engineering |
| 3 | Modern | 3 | 30 | 0.40 | 5 steel, 5 lumber | 3 | Modern Forts |

## Deferred (REQ-P2-02)

- Town tiles: forts are province-scoped (DR-20261108-04).
- Gates and dedicated sortie orders; province-lane terrain (HILL/WOODS/TOWN).

## Architecture

| File | Role |
|------|------|
| `scripts/rules/fort_rules.gd` | level tables, wall soak, battery, build gates |
| `scripts/rules/siege_lanes.gd` | wall/behind lanes, sortie exposure, lane casualties |
| `scripts/rules/quick_battle_battery.gd` | virtual guns: spawn, hit, fire, downgrade |
| `scripts/rules/auto_siege.gd` | auto-resolve counter-battery and downgrade |
| `scripts/world/province_state.gd` | `fort_level` state |
| `scripts/rules/civilian_work.gd` | `build_fort` validation and completion |
| `scripts/rules/army_modifiers.gd` | siege keys per side |
| `scripts/rules/army_combat.gd` | applies the siege keys in one exchange |
| `scripts/ui/province_panel.gd` | fort line in the province dossier |

Node-free (`REQ-P3-03`): the panel reads `fort_level`, combat reads `FortRules`.
