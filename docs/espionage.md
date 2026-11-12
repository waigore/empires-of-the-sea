# Espionage

Spies observe rival Great Powers, lift research and screen the home provinces
(wiki: [civilian-units § Spy](https://github.com/waigore/empires-of-the-sea/wiki/civilian-units),
[research-state § Spy RP boost](https://github.com/waigore/empires-of-the-sea/wiki/research-state)).

**Pillars:** P2 rules fidelity, P3 pure/testable rules, P4 no per-frame work,
P5 hidden spies leave no trace.

## Implemented

- **Roster:** Spy trains at the capital for 2,000 cash + 4 paper. It may enter
  any land province, including rival Great Powers, Minor Nations and Tribes.
- **Presence reveal** (`SpyNetworks`, `CivilianMovement`): a spy in a non-owner
  province holds that province's already-charted tiles fully visible at
  end-of-turn. Presence never promotes `unknown` terrain, never reveals an
  unprospected mineral, and the province fogs immediately when the last spy
  leaves (no grace timer).
- **Invisibility:** rival spies are never drawn, hovered or selectable on the
  human map (`CivilianLayer.viewer_faction`); the AI never sees human spies.
- **Counter-espionage** (`counter_spy`): an ongoing order on any owned province.
  One spy on it anywhere gives the whole empire a +5% kill chance against enemy
  spies in every owned province — both regions, from the one screen — and
  survivors roll 10% defection per turn. A turned spy changes crown and stays
  where it stood.
- **Spy death:** a killed spy cools relations between its owner and the
  territory owner by 8 and counts as that turn's interaction (wiki: diplomacy
  § Spy-death penalty).
- **Research boost:** each observed rival Great Power adds +15% RP to every
  occupied slot researching a tech that rival already knows (funding ≥ Low).
  The boost stacks per rival, adds to Industrial Funding before one floor, and
  spies killed that turn do not contribute.
- **Court reports:** after resolution the human receives one digest per
  observed rival covering this turn's diplomatic message, battles, provinces
  taken or lost, and technologies completed. Never the rival's hidden agenda.
  The same lines stay in the session (`play.court_reports`) and the court
  panel shows the despatch under that crown's chronicle, so a report is still
  readable after its toast has gone. Eight lines at most; opponents the viewer
  has not met stay "Unknown faction".
- **Persistence:** spy units and owners ride the existing civilian and save
  tables; the screen is rebuilt from `counter_spy` work orders.

## AI use

`AiSpyPlanner` keeps a spy in a foreign province on station, walks idle spies
toward the nearest unobserved rival Great Power province (one spy per rival
first), and raises a counter-espionage screen at home while at war. Rivals open
with a spy and train more after their builder/engineer/explorer base.
Rival research is live (`AiResearchPlanner`), so the AI's own spies earn the
same +15% boost the player does.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/spy_networks.gd` | presence hosts, qualifying rivals, RP boost |
| `scripts/rules/spy_rules.gd` | screen, dice, kills, defections |
| `scripts/rules/civilian_movement.gd`, `civilian_work.gd` | entry and order |
| `scripts/ai/ai_spy_planner.gd` | rival work and march policy |
| `scripts/map/map_play_spies.gd` | resolution and court digest |
| `scripts/map/map_play_espionage.gd`, `map_play_spy_ai.gd` | player/AI boost wiring |
| `scripts/map/civilian_layer.gd` | invisibility on the map |

## Tests

`test_espionage`, `test_intel_rules`, `test_visibility`, `test_ai_rules`,
`test_research_rules`.

```bash
gd-tools test --coverage --min 80
```
