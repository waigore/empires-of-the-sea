# Land armies

Land military slice: regiment roster, persistent armies, the Home Army, army
marches, field battles and unopposed capture.

**Pillars:** P2, P3 (rules/view), P1 (map feedback), P4 (no per-frame land sim),
P5 (batched orders).

**Wiki:** [military-armies](https://github.com/waigore/empires-of-the-sea/wiki/military-armies),
[military-units](https://github.com/waigore/empires-of-the-sea/wiki/military-units),
[combat](https://github.com/waigore/empires-of-the-sea/wiki/combat),
[military-generals](https://github.com/waigore/empires-of-the-sea/wiki/military-generals).

## Implemented

- **Roster** (`RegimentCatalog`): all 29 wiki regiments with FPN/FPM/RNG/DEF/
  MVR, category, era and the treasury build cost. Infantry/cavalry/
  artillery and garrison-recovery helpers derive from that one table.
- **Armies** (`ArmyState`): a province-stationed container of stable `unit_<n>`
  regiments; each belongs to one army.
- **Home Army:** one per faction at its capital, never deleted (even empty)
  and never marches. Detach regiments to form field armies.
- **Split/combine:** same province and owner only; the Home Army is always the
  merge target when present; emptied field armies are removed.
- **Movement:** one march per turn. Any owned province connected through own
  territory is reachable (interior lines); enemy or neutral land must border
  the army. Home Armies refuse every march.
- **Upkeep:** 1–3 food per regiment by category/era (cavalry and artillery 3),
  eaten before the navy and workers in Consumption.
- **Combat:** auto-resolve at end of turn. Side strength is `Σ (FPN + FPM)`;
  casualties follow the wiki ratio bands (0.15/1.0, 0.3/0.6, 0.5/0.4, 1.0/0.15)
  and are taken weakest-first. Army elimination is applied before a province
  flips. Multiple defending armies share one side; attackers act in cavalry
  initiative order. Mutual annihilation restores `ceil(20%)` of the defender's
  starting regiments as its era's most advanced infantry when another attacker
  remains.
- **Unopposed capture:** a Great Power army ending in hostile or neutral land
  with no defenders or armed third faction takes it at the start of combat.
- **Dossier** (`ARMY` panel): composition, strength, food, per-regiment Detach,
  Detach all, Combine and dock left/right. `TROOPS` chip counts every region.
- Hostility is non-ownership.

## Deferred (REQ-P2-02)

Regiment training (materials, workers, treasury deduction) · generals, medals,
pre-combat binding · terrain, feeding, difficulty and leader modifiers · forts,
siege walls, emplaced guns · Quick Battle · multi-attacker RNG tie-break ·
minor military parity and in-place upgrades · AI marches · naval transport
between regions.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/regiment_catalog.gd` | stats, costs, category helpers, recovery type |
| `scripts/rules/army_state.gd` | container, Home Army flag, split/combine, prune |
| `scripts/rules/army_movement.gd` | destinations, validation, `apply_move` |
| `scripts/rules/army_combat.gd` | initiative, ratio bands, casualties, capture |
| `scripts/map/army_marker.gd`, `army_layer.gd` | standards, per-region rosters, orders |
| `scripts/map/map_play_armies.gd` | selection, detach/merge, battle reports |
| `scripts/ui/army_panel.gd` | dockable dossier |
| `scripts/economy/economy_controller.gd` | army rations into Consumption |
| `scripts/map_screen.gd` | intents + end-of-turn wiring |

No node deps in rules (`REQ-P3-03`). Orders: `ArmyLayer.order` →
`ArmyMovement.apply_move`. Combat: `ArmyLayer.resolve_battles` →
`ArmyCombat.resolve_turn`.

## Controls

| Action | Desktop | Touch |
|--------|---------|-------|
| Select army | click standard | tap standard |
| March | click highlighted province | tap highlighted province |
| Detach / combine | dossier buttons | dossier buttons |
| Cancel | `Esc` | dossier Close |

## Tests

`test_regiment_catalog`, `test_army_state`, `test_army_movement`,
`test_army_combat`, `test_army_orders`, `test_map_screen`.

```bash
gd-tools test --coverage --min 80
```
