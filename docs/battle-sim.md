# Battle Simulator

A visual playtesting instrument for Quick Battle and sieges. It builds a
one-province sandbox and runs **the live resolver** (`QuickBattle`), so a number
it prints is the number a game turn prints (`REQ-P2-03`).

**Pillars:** P2, P3, P5. **Wiki:**
[quick-battle](https://github.com/waigore/empires-of-the-sea/wiki/quick-battle),
[siege-mechanics](https://github.com/waigore/empires-of-the-sea/wiki/siege-mechanics).

## Launch

```bash
tools/run.sh scenes/battle_sim.tscn
```

The wrapper imports the project first; a bare `godot --path . scenes/battle_sim.tscn`
fails on a fresh clone (see [testing.md](testing.md)).

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

- The plate paints a generated period landscape per terrain, with the fort wall
  and its three gatehouses standing on it. A breached gate is a jagged hole
  with rubble spilled onto the field.
- The despatch lists every round's actions with the game's own copy: losses,
  mauled men, guns silenced, gates breached, the battery taking the blow.
- The aftermath adds the ground modifiers, the siege line (lanes, guns, breach),
  losses by regiment type, wounds and chevrons, and the outcome stamp.
- The readout prints what the rules read: deployment limits, terrain
  multipliers, wall reduction, gate threshold, lanes and guns.

## Scenarios worth running

- A pike-only garrison behind a Stone fort: it cannot shoot, so it sorties.
- Muskets without guns: the wall turns the blow aside, no gate falls.
- Guns plus muskets against a Wood fort: silence the battery, then beat the wall
  until a gate opens and the behind lane bleeds.
- Assault into TOWN versus OPEN: compare the same men and plan.
- A castle on a hillside: the ground stays HILL, so the approach is uphill.

## Scope

The simulator is a development tool, not a shipped screen. It mutates a
throwaway model and army pair; nothing is saved. `BattleScenario` is node-free
rules code and is unit-tested; the screen is a thin view (`REQ-P3-01`,
`REQ-P3-03`).

## Architecture

| File | Role |
|------|------|
| `scripts/rules/battle_scenario.gd` | builds the sandbox and runs `QuickBattle` |
| `scripts/ui/battle_sim_setup.gd` | setup rail; emits run/step/reset intents |
| `scripts/ui/battle_sim_screen.gd` | plate, despatch log and rules readout |
| `scripts/ui/battle_plate.gd` | painted ground, wall, breach and miniatures |
| `scenes/battle_sim.tscn` | the launchable scene |

The plate is generated art (`assets/art/battle/`): a painted panorama per
terrain, plus cut-out walls, miniatures and rubble. Prompts and build script:
[`tools/art/battle-plate.md`](../tools/art/battle-plate.md).

## Tests

`test_battle_rules` proves the sandbox resolves the same battle as a direct
`QuickBattle.resolve_exchange` call and that the scene fights, steps and resets.
Run it with `gd-tools test tests/test_battle_rules.gd`.
