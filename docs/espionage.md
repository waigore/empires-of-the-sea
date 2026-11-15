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
  province holds its charted tiles visible. It never promotes `unknown` terrain
  or an unprospected mineral; a province the last spy leaves keeps its charter
  five turns, then fogs (wiki: fog-and-exploration).
- **Invisibility:** rival spies are never drawn, hovered or selectable
  (`CivilianLayer.viewer_faction`); the AI never sees human spies.
- **Counter-espionage** (`counter_spy`): an ongoing order on any owned province.
  One spy anywhere gives the empire +5% kill chance against enemy spies in every
  owned province, and survivors roll 10% defection a turn; a turned spy changes
  crown and stays where it stood.
- **Spy death:** a killed spy cools relations by 8 and counts as that turn's
  interaction (wiki: diplomacy § Spy-death penalty).
- **Research boost:** each observed rival Great Power adds +15% RP to slots
  researching a tech it already knows (funding ≥ Low), stacking per rival and
  added before one floor; spies killed that turn do not count.
- **Court reports:** one digest per observed rival after resolution — its
  diplomatic message, battles, provinces taken or lost, technologies finished;
  never its hidden agenda. The lines stay in `play.court_reports` and print
  under that crown's chronicle. Eight lines at most.
- **Persistence:** spies ride the civilian and save tables; the screen is
  rebuilt from `counter_spy` orders.

## The crown's eyes

`SpyLedger` + `SpyLedgerPanel` (DR-20261115-10): the court ledger's **EYES ›**
door (or `I`) opens one sheet — every spy with the duty its posting earns
(`shadow`, `watch`, `screen`, `idle`, `aboard`), every Great Power marked
shadowed or unobserved, and whether the screen is up. Visit opens the spy. Every
reading is the rules' own predicate; the sheet moves nothing.

## AI use

`AiSpyPlanner` keeps a spy in a foreign province on station, walks idle spies
toward the nearest unobserved rival Great Power province (one spy per rival
first), and raises a counter-espionage screen at home while at war. Rivals open
with a spy and train more after their builder/engineer/explorer base.
Rival research is live, so AI spies earn the same +15% boost.

## Architecture

| File | Role |
|------|------|
| `scripts/rules/spy_networks.gd` | presence hosts, qualifying rivals, RP boost |
| `scripts/rules/spy_rules.gd` | screen, dice, kills, defections |
| `scripts/rules/spy_charter.gd` | the departed spy's charter |
| `scripts/rules/spy_ledger.gd` | the crown's eyes: duties, courts, screen |
| `scripts/rules/civilian_movement.gd`, `civilian_work.gd` | entry and order |
| `scripts/ai/ai_spy_planner.gd` | rival work and march policy |
| `scripts/map/map_play_spies.gd` | resolution and court digest |
| `scripts/map/map_play_espionage.gd`, `map_play_spy_ai.gd` | player/AI boost wiring |
| `scripts/map/civilian_layer.gd` | invisibility on the map |

## Tests

`test_spycraft_rules`, `test_spy_ledger`, `test_court_ui_parts`, `test_ai_rules`,
`test_research_rules`.

```bash
gd-tools test --coverage --min 80
```
