# Forts and sieges

Walls raised on owned land, and the siege they create.

**Pillars:** P2, P3 (rules/view split), P5 (visible outcomes), P1 (dossier).

**Wiki:** [siege-mechanics](https://github.com/waigore/empires-of-the-sea/wiki/siege-mechanics),
[combat](https://github.com/waigore/empires-of-the-sea/wiki/combat) § Battle
Mode, [tech-tree-military](https://github.com/waigore/empires-of-the-sea/wiki/tech-tree-military).

## Implemented

- **Storage:** `ProvinceState.fort_level` 0–3, saved with the world
  (`SaveCodec`). A captured province keeps its walls.
- **Build order:** Engineers take `Fort` on a tile of their crown's province;
  the fort is province-scoped. Materials are paid on assignment, never
  refunded.
- **Multi-turn:** one turn per level (L1 1, L2 2, L3 3). A completion lands the
  ordered level; a duplicate project cannot leap a level or its gate.
- **Tech gates:** L2 needs Mine Engineering, L3 needs Modern Forts.
- **Battle mode:** `fort_level == 0` is field, `≥ 1` siege; reports carry
  `battle_mode` and `fort_level`.
- **Walls (auto-resolve):** attacker strength drops by wall HP (10 / 20 / 30)
  before the ratio band, floored at zero.
- **Defender losses:** the band's defender share is scaled by 1 − damage
  reduction (0.75 / 0.55 / 0.40), so walls also spare the garrison.
- **Walls (Quick Battle):** blows that reach the defenders take the same
  0.75 / 0.55 / 0.40 cut; only the battery is unsheltered.
- **Aftermath:** the plate names the fort, wall cut and, if the battery is
  silenced, the level it falls to.
- **Emplaced battery:** the defender gains `guns × strength` of its emplaced
  type — 1 / 2 / 3 pieces. Quality follows the researched line
  Royal → Heavy (Heavy Emplaced Artillery) → Siege (Emplaced Siege Guns);
  unresearched courts keep Royal Artillery. Emplaced pieces are an aggregate
  bonus, never field regiments.
- **Dossier:** the province panel prints the fort and its emplaced gun count.

## Costs and numbers

| Level | Fort | Guns | Wall HP | Loss scale | Cost | Turns | Tech |
|------:|------|-----:|--------:|-----------:|------|------:|------|
| 1 | Wood | 1 | 10 | 0.75 | 3 lumber, 3 bronze | 1 | — |
| 2 | Stone | 2 | 20 | 0.55 | 4 lumber, 4 bronze | 2 | Mine Engineering |
| 3 | Modern | 3 | 30 | 0.40 | 5 steel, 5 lumber | 3 | Modern Forts |

## Deferred (REQ-P2-02)

- Quick Battle siege lanes: per-position wall/behind-wall units, gates and
  sorties wait on the lane model. Wall damage reduction, virtual guns and the
  "all guns destroyed → fort −1" downgrade are implemented.
- Distinct town tiles: forts are province-scoped because provinces carry no
  town tile (see DR-20261108-04).

## Architecture

| File | Role |
|------|------|
| `scripts/rules/fort_rules.gd` | level tables, wall soak, emplaced battery, build gates |
| `scripts/world/province_state.gd` | `fort_level` state |
| `scripts/rules/civilian_work.gd` | `build_fort` validation, cost, progress, completion |
| `scripts/rules/army_modifiers.gd` | siege keys for each side (`wall_hp`, `emplaced`, `loss_scale`) |
| `scripts/rules/army_combat.gd` | applies the siege keys inside one exchange |
| `scripts/ui/province_panel.gd` | fort line in the province dossier |

Rules stay node-free (`REQ-P3-03`): the panel reads `fort_level`, combat reads
`FortRules`; both share one table.
