# Forts and sieges

Walls an Engineer raises on owned land, and the auto-resolve siege they create.

**Pillars:** P2, P3 (rules/view split), P5 (visible outcomes), P1 (dossier).

**Wiki:** [siege-mechanics](https://github.com/waigore/empires-of-the-sea/wiki/siege-mechanics),
[combat](https://github.com/waigore/empires-of-the-sea/wiki/combat) § Battle
Mode, [tech-tree-military](https://github.com/waigore/empires-of-the-sea/wiki/tech-tree-military).

## Implemented

- **Storage:** `ProvinceState.fort_level` 0–3, saved and restored with the
  world (`SaveCodec`). A captured province keeps its walls; only the garrison
  changes.
- **Build order:** Engineers take `Fort` in their dossier on a tile of their own
  crown's province; the fort belongs to the province, not the tile. Materials
  are paid on assignment and never refunded.
- **Multi-turn:** one turn per level reached (L1 1, L2 2, L3 3). Each completion
  raises the province one level.
- **Tech gates:** L2 needs Mine Engineering, L3 needs Modern Forts.
- **Battle mode:** `fort_level == 0` is a field battle (unchanged); `fort_level
  ≥ 1` is a siege. Every land-battle report carries `battle_mode` and
  `fort_level`.
- **Walls (auto-resolve):** attacking side strength is reduced by the wall HP
  (10 / 20 / 30) before the ratio band is read, floored at zero.
- **Defender losses:** the band's defender share is scaled by 1 − damage
  reduction (0.75 / 0.55 / 0.40), so walls also spare the garrison.
- **Emplaced battery:** the defender's side gains `guns × strength` of its
  emplaced gun type — 1 / 2 / 3 pieces. Quality follows the researched line
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

- Quick Battle siege lanes: wall HP soak and damage reduction for auto-resolve
  only; per-position "on the wall"/"behind the wall", gates and sorties wait on
  the lane model.
- Virtual emplaced gun entities and the "all guns destroyed → fort −1" downgrade
  (Quick Battle path only; the wiki excludes auto-resolve).
- Distinct town tiles: forts are province-scoped because provinces carry no
  town tile yet (see DR-20261108-04).

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
