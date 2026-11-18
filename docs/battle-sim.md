# Battle Simulator

A visual playtesting instrument for Quick Battle and sieges: a one-province
sandbox over **the live resolver** (`QuickBattle`), so a number it prints is the
number a game turn prints (`REQ-P2-03`).

**Pillars:** P2, P3, P5. **Wiki:**
[quick-battle](https://github.com/waigore/empires-of-the-sea/wiki/quick-battle),
[siege-mechanics](https://github.com/waigore/empires-of-the-sea/wiki/siege-mechanics).

## Launch

```bash
tools/run.sh scenes/battle_sim.tscn
```

The wrapper imports first; a bare `godot --path . scenes/battle_sim.tscn`
fails on a fresh clone ([testing.md](testing.md)).

## Layout

Three columns on a desktop; below 900 points they stack into one scrolling
column (`REQ-P1-05`, `REQ-P5-07`).

## Controls

| Control | What it changes |
|---------|-----------------|
| Ground | OPEN / HILL / WOODS / TOWN / MARSH lane terrain |
| Fort | none / Wood / Stone / Modern (`fort_level` 0–3) |
| Attacker, Defender | three regiment slots a side, 0–20 each |
| Attacker plan / Defender plan | aggressive / balanced / defensive action script |
| Seed | deterministic quick-battle seed |
| Fight | resolve and show the aftermath |
| Next round | step the recorded rounds on the plate |
| Reset | clear the record and start over |

## What it shows

- The plate paints a period landscape per terrain, with the fort's wall and
  three gatehouses on it. A breached gate is a jagged hole with rubble spilled
  onto the field.
- The despatch lists every round's actions with the game's own copy: losses,
  mauled men, guns silenced, gates breached, the battery taking the blow, and
  the wing it fell on.
- The aftermath adds the ground, the wings and the ones broken, the siege line
  (lanes, guns, breach), losses by type, wounds and chevrons, and the outcome
  stamp.
- The readout prints the rules' own reads: deployment limits, terrain,
  wall reduction, gate threshold, lanes and guns.

## Scenarios worth running

- A pike-only garrison behind a Stone fort: it cannot shoot, so it sorties.
- Muskets without guns: the wall turns the blow aside, no gate falls.
- Guns plus muskets against a Wood fort: silence the battery, then beat the wall
  until a gate opens and the behind lane bleeds.
- Assault into TOWN versus OPEN: compare the same men and plan.

## Scope

The simulator is a development tool, not a shipped screen: it mutates a
throwaway model and army pair, saving nothing. `BattleScenario` is node-free
rules code and is unit-tested; the screen is a thin view (`REQ-P3-01`,
`REQ-P3-03`).

## Architecture

| File | Role |
|------|------|
| `scripts/rules/battle_scenario.gd` | builds the sandbox and runs `QuickBattle` |
| `scripts/ui/battle_sim_setup.gd` | setup rail; emits run/step/reset intents |
| `scripts/ui/battle_sim_screen.gd` | plate, despatch log and rules readout |
| `scripts/ui/battle_plate*.gd` | facade + ground, wall, figure painters |
| `scenes/battle_sim.tscn` | the launchable scene |

The plate is generated art (`assets/art/battle/`): a painted panorama per
terrain, plus cut-out walls, miniatures and rubble. Prompts and build script:
[`tools/art/battle-plate.md`](../tools/art/battle-plate.md).

## Tests

`test_battle_rules` proves the sandbox resolves the same battle as a direct
`QuickBattle.resolve_exchange` call and that the scene fights, steps and resets.
Run it with `gd-tools test tests/test_battle_rules.gd`.
