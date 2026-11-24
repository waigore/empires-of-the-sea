# Battle Simulator

A playtesting instrument for Quick Battle and sieges: a one-province
sandbox over **the live resolver** (`QuickBattle`), so a number it prints is the
number a game turn prints (`REQ-P2-03`).

**Pillars:** P2/P3/P5. **Wiki:**
[quick-battle](https://github.com/waigore/empires-of-the-sea/wiki/quick-battle),
[siege-mechanics](https://github.com/waigore/empires-of-the-sea/wiki/siege-mechanics).

## Launch

```bash
tools/run.sh scenes/battle_sim.tscn
```

The wrapper imports first; a bare `godot --path . scenes/battle_sim.tscn` fails
on a fresh clone ([testing.md](testing.md)). Three columns on a desktop; below
900 points they stack into one scrolling column (`REQ-P1-05`, `REQ-P5-07`).

## Controls

| Control | What it changes |
|---------|-----------------|
| Ground | OPEN / HILL / WOODS / TOWN / MARSH lane terrain |
| Fort | none / Wood / Stone / Modern / Bastion / Star (`fort_level` 0–5) |
| Battery | the garrison's line — Royal / Heavy / Siege (`FortRules.EMPLACED_TECHS`) |
| Attacker, Defender | three slots a side, 0–20 each |
| Attacker plan / Defender plan | aggressive / balanced / defensive script |
| Attacker medals / Defender medals | the commander's chevrons, 0–4 (strength ×1.0–×1.4) |
| Fight | resolve and show the aftermath |
| Next round | step the recorded rounds |
| Reset | clear the record |

Every lever is one the resolver reads: a later gun line carries the studies it
builds on, and medals ride in as the commander's rank. A lone attacker's battle
is deterministic for its plan, so there is no seed dial — the seed breaks
initiative ties between rival attackers only
([combat](https://github.com/waigore/empires-of-the-sea/wiki/combat) § Initiative).

## What it shows

- The plate paints a landscape per terrain with the fort's wall and three
  gatehouses; a breached gate is a jagged hole with rubble.
- The despatch lists every round's actions in the game's copy — losses, mauled
  men, guns silenced, gates breached, the battery taking the blow — then the
  aftermath: ground, the wings broken, the siege line, losses by type, wounds,
  chevrons and the outcome.
- The readout prints limits, terrain, wall reduction, gate threshold, lanes,
  guns and levers set.

## Scenarios worth running

- A pike-only garrison behind a Stone fort: it cannot shoot, so it sorties.
- Muskets without guns: the wall turns the blow aside, no gate falls.
- Guns against a Wood fort: silence the battery, then beat the wall until a gate
  opens — and run the same wall under Royal, Heavy and Siege guns.

## Scope

A development tool, not a shipped screen: it mutates a throwaway model and army
pair, saving nothing. `BattleScenario` is node-free rules code and is unit-tested;
the screen is a thin view (`REQ-P3-01`, `REQ-P3-03`).

## Architecture

| File | Role |
|------|------|
| `scripts/rules/battle_scenario.gd` | builds the sandbox and runs `QuickBattle` |
| `scripts/ui/battle_sim_setup.gd` | setup rail; emits run/step/reset intents |
| `scripts/ui/battle_sim_screen.gd` | plate, despatch log and rules readout |
| `scripts/ui/battle_plate*.gd` | facade + ground, wall, figure painters |
| `scenes/battle_sim.tscn` | the launchable scene |

`test_a_battle_rules` proves the sandbox resolves the same battle as a direct
`QuickBattle.resolve_exchange` call and that the scene fights, steps and resets.
