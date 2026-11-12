# Field hospital train

Tents and a surgeon's chest that march with one army (wiki:
[combat](https://github.com/waigore/empires-of-the-sea/wiki/combat) § Regiment
condition; DR-20261112-07). A field hospital train is **not** a province
building: the province record never knows it, and the dossier prints it on the
standard that carries it.

**Pillars:** P2 rules, P3 pure, P5 discoverability, P1 court.

## Raising it

The army dossier offers **Pitch a field hospital** for the crown's own army when
all of these hold (a blocked order still shows, disabled, with the rules' own
reason as its caption — `REQ-P5-03`):

| Gate | Value |
|------|-------|
| Land | the province the army stands in is the crown's |
| Army | not embarked, not empty, and carries no train yet |
| Tech | Organised Regiments |
| Price | 2 lumber + 1 fabric from the central stockpile, paid at once |

No build time: a train is equipment, like a regiment's muster, not a project.
One train per army.

## What it returns

- **Rest** — at turn start the army recovers `ceil(40% × max)` health wherever
  it stands, the Field hospital's share. The better of the train and the
  province's ward applies, never both (a General hospital still gives 55%).
- **No wear relief** — the battle-wear triage stays the province's walls
  (DR-20261111-12); tents do not shelter a line, and a train never changes the
  wounds a defeat leaves.
- **Rations** — the staff eat 2 food a turn inside the army's own upkeep line,
  so a hungry larder starves the train with the men and there is no separate
  staffing flag (`REQ-P4-01`).

## Where it goes

The train travels with its standard at no extra cost, boards a squadron with it,
and is saved with the army. A split leaves it with the parent standard; when a
detach empties a field army the train marches with the men who are left; a
combine keeps one train if either army had one. Rival planners pitch none yet.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/hospital_rules.gd` | the table, the check, the better-of tempo |
| `scripts/rules/army_state.gd` | the flag, rations, split/combine, save |
| `scripts/rules/army_movement.gd` | the turn-start rest tick |
| `scripts/map/map_play_army_muster.gd` | the order: materials, then the flag |
| `scripts/map/map_play_armies.gd` | the dossier's caption and the action door |
| `scripts/ui/army_panel.gd` | the strength line and the button |

## Tests

`tests/test_land_battle_rules.gd` (the hospital and train cases).

```bash
gd-tools test --no-cache tests/test_land_battle_rules.gd
```
